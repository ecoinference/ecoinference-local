import Foundation
import os

private let needleLog = Logger(subsystem: "ai.ecoinference.app", category: "NeedleEmbedder")

/// Cactus Needle 3 as a fixed feature extractor for the router's semantic
/// facts (docs/ROUTING.md §4 — adopted design). The model ships once; ALL
/// tunable intelligence (exemplar texts, thresholds, centering mean) lives in
/// `ExemplarConfig` JSON — bundled default plus live updates via Firebase
/// Remote Config key `router_exemplars`, same version-gated pattern as
/// `router_rules`. Mirrors Android NeedleEmbedder.kt.
///
/// Failure contract: every failure path leaves `semanticFacts` returning nil
/// and the router falls back to keyword facts. Routing must never block or
/// crash chat. Engine unavailable (weights not vendored, stub bridge, init
/// error) is a normal state, not an error.
///
/// Threading: the needle C API is one process-global, NOT thread-safe model.
/// Every native call runs on `queue`; callers may invoke `semanticFacts`
/// from any thread except the queue itself (it blocks on queue.sync).
final class NeedleEmbedder {

    static let shared = NeedleEmbedder()

    struct ExemplarConfig: Codable {
        let version: Int
        /// fact name -> exemplar texts (embedded once per config load).
        let categories: [String: [String]]
        /// fact name -> strict-greater max-cosine threshold.
        let thresholds: [String: Double]
        /// Fixed centering mean, dim must match the model (3072). Nil = no centering.
        let mean: [Double]?
    }

    private let queue = DispatchQueue(label: "ai.ecoinference.needle")
    private let stateLock = NSLock()
    private var isReady = false

    // Guarded by queue: mutated only in blocks running on it.
    private var dim = 0
    private var config: ExemplarConfig?
    private var mean: [Float]?
    private var exemplars: [String: [[Float]]] = [:]

    private init() {}

    /// Fire-and-forget engine + bundled-config startup; call once at launch.
    func start() {
        queue.async { self.initializeOnQueue() }
    }

    /// Version-gated live update (Remote Config `router_exemplars`).
    func applyConfigIfNewer(_ newConfig: ExemplarConfig) {
        queue.async {
            if newConfig.version > (self.config?.version ?? 0) {
                self.applyConfigOnQueue(newConfig)
            }
        }
    }

    /// Semantic facts for one prompt, or nil when the embedder is unavailable
    /// or anything goes wrong — callers keep their keyword-derived facts.
    /// ~8-10 ms per prompt on M-series Macs; the Lenovo TB336FU measurement
    /// is still owed (ROUTING.md §4 item 2).
    func semanticFacts(prompt: String) -> [String: FactValue]? {
        stateLock.lock()
        let ready = isReady
        stateLock.unlock()
        guard ready else { return nil }
        return queue.sync {
            guard let config else { return nil }
            guard let vec = embedOnQueue(ExemplarScorer.normalize(prompt)) else { return nil }
            return ExemplarScorer.semanticFacts(
                promptVec: vec, mean: mean, exemplars: exemplars, thresholds: config.thresholds
            )
        }
    }

    // MARK: - queue-thread internals

    private func initializeOnQueue() {
        guard let url = Bundle.main.url(forResource: "needle3", withExtension: "cact"),
              let cact = try? Data(contentsOf: url) else {
            needleLog.info("weights not bundled (run fetch_needle.sh) — router stays on keyword facts")
            return
        }
        let d = NeedleBridge.loadModel(from: cact)
        guard d > 0 else {
            needleLog.info("engine unavailable: \(NeedleBridge.lastErrorMessage())")
            return
        }
        dim = Int(d)
        stateLock.lock(); isReady = true; stateLock.unlock()
        needleLog.info("engine ready, dim=\(self.dim)")
        if let next = config ?? loadBundledConfig() {
            applyConfigOnQueue(next)
        }
    }

    private func loadBundledConfig() -> ExemplarConfig? {
        guard let url = Bundle.main.url(forResource: "default_router_exemplars", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            needleLog.warning("bundled exemplar config missing")
            return nil
        }
        do {
            return try JSONDecoder().decode(ExemplarConfig.self, from: data)
        } catch {
            needleLog.warning("bundled exemplar config unreadable: \(error.localizedDescription)")
            return nil
        }
    }

    private func applyConfigOnQueue(_ newConfig: ExemplarConfig) {
        config = newConfig
        stateLock.lock(); let ready = isReady; stateLock.unlock()
        guard ready else { return }   // embedded later, at the end of initializeOnQueue
        var m: [Float]? = nil
        if let list = newConfig.mean {
            if list.count != dim {
                needleLog.warning("config v\(newConfig.version): mean dim \(list.count) != \(self.dim), ignoring mean")
            } else {
                m = list.map { Float($0) }
            }
        }
        var vectors: [String: [[Float]]] = [:]
        for (cat, texts) in newConfig.categories {
            vectors[cat] = texts.compactMap { raw in
                guard let v = embedOnQueue(ExemplarScorer.normalize(raw)) else { return nil }
                return m.map { ExemplarScorer.center(v, mean: $0) } ?? v
            }
        }
        mean = m
        exemplars = vectors
        needleLog.info("exemplar config v\(newConfig.version) applied: \(vectors.values.map(\.count).reduce(0, +)) vectors")
    }

    private func embedOnQueue(_ text: String) -> [Float]? {
        var out = [Float](repeating: 0, count: dim)
        let r = out.withUnsafeMutableBufferPointer { buf in
            NeedleBridge.embedText(text, into: buf.baseAddress, capacity: dim)
        }
        guard r >= 0 else {
            needleLog.warning("embed failed: \(NeedleBridge.lastErrorMessage())")
            return nil
        }
        return out
    }
}

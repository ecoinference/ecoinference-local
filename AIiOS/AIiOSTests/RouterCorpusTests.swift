import XCTest
// No `@testable import` — RuleEngine.swift, RouterFactExtractor.swift and
// RouterModels.swift are compiled directly into this standalone test bundle
// (same pattern as AgentLoopTests). Mirrors Android's RouterCorpusTest.kt;
// both read the *same* corpus at tests/router/corpus.jsonl.
// Design and rationale: docs/ROUTING.md §2.

final class RouterCorpusTests: XCTestCase {

    // MARK: - Corpus schema (must stay in sync with the JSONL and Android)

    private struct CaseContext: Decodable {
        let turns: Int
        let hasImage: Bool
        let localSupportsImage: Bool

        private enum CodingKeys: String, CodingKey {
            case turns, hasImage, localSupportsImage
        }

        init() {
            turns = 0
            hasImage = false
            localSupportsImage = true
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            turns = try c.decodeIfPresent(Int.self, forKey: .turns) ?? 0
            hasImage = try c.decodeIfPresent(Bool.self, forKey: .hasImage) ?? false
            localSupportsImage = try c.decodeIfPresent(Bool.self, forKey: .localSupportsImage) ?? true
        }
    }

    private struct CorpusCase: Decodable {
        let id: String
        let prompt: String
        let expect: String
        let because: String
        let context: CaseContext
        let notes: String
        let knownMiss: Bool

        private enum CodingKeys: String, CodingKey {
            case id, prompt, expect, because, context, notes
            case knownMiss = "known_miss"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            prompt = try c.decode(String.self, forKey: .prompt)
            expect = try c.decode(String.self, forKey: .expect)
            because = try c.decodeIfPresent(String.self, forKey: .because) ?? ""
            context = try c.decodeIfPresent(CaseContext.self, forKey: .context) ?? CaseContext()
            notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
            knownMiss = try c.decodeIfPresent(Bool.self, forKey: .knownMiss) ?? false
        }
    }

    // MARK: - Loading

    /// Repo root, resolved from this file's location so the test reads the same
    /// shared corpus and rules regardless of simulator/runner working directory.
    /// Simulators share the Mac filesystem, so #filePath resolution works.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AIiOSTests/
            .deletingLastPathComponent()   // AIiOS/
            .deletingLastPathComponent()   // repo root
    }

    private func loadCases() throws -> [CorpusCase] {
        let url = repoRoot.appendingPathComponent("tests/router/corpus.jsonl")
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(CorpusCase.self, from: Data($0.utf8)) }
    }

    private func loadRuleSet() throws -> RouterRuleSet {
        let url = repoRoot.appendingPathComponent("AIiOS/AIiOS/default_router_rules.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RouterRuleSet.self, from: data)
    }

    /// Mirrors RouterService.decide() minus Firebase: same facts, same engine.
    private func decide(_ c: CorpusCase, ruleSet: RouterRuleSet) -> RuleEngine.Outcome {
        let history = (0..<c.context.turns).map { InferenceMessage(role: "user", text: "turn \($0)") }
        var facts = RouterFactExtractor.extract(prompt: c.prompt, history: history, hasImage: c.context.hasImage)
        facts["localSupportsImage"] = .bool(c.context.localSupportsImage)
        return RuleEngine().decide(facts: facts, ruleSet: ruleSet)
    }

    private func allDecisions() throws -> [String: String] {
        let ruleSet = try loadRuleSet()
        return try loadCases().reduce(into: [String: String]()) { result, c in
            result[c.id] = decide(c, ruleSet: ruleSet).decision
        }
    }

    // MARK: - Tests

    func testCorpusCases_withoutKnownMiss_routeAsExpected() throws {
        let ruleSet = try loadRuleSet()
        for c in try loadCases() where !c.knownMiss {
            let outcome = decide(c, ruleSet: ruleSet)
            XCTAssertEqual(
                outcome.decision, c.expect,
                "\(c.id): rule=\(outcome.ruleId ?? "default") — \(c.because)"
            )
        }
    }

    /// Reports the four metrics from docs/ROUTING.md §2 and dumps this
    /// platform's decisions. Never fails — known_miss cases are *expected* to
    /// be wrong until a semantic-fact replacement lands; the conversion count
    /// is the instrument that decides whether one earns its cost.
    func testCorpusMetrics_reportAndDumpDecisions() throws {
        let ruleSet = try loadRuleSet()
        let cases = try loadCases()
        let decisions = try allDecisions()

        let labeled = cases.filter { !$0.knownMiss }
        let misses = cases.filter { $0.knownMiss }
        let falseLocal = labeled.filter { $0.expect == "cloud" && decisions[$0.id] == "local" }
        let falseCloud = labeled.filter { $0.expect == "local" && decisions[$0.id] == "cloud" }
        let retainedLocal = labeled.filter { decisions[$0.id] == "local" }
        let converted = misses.filter { decisions[$0.id] == $0.expect }

        print("── router corpus metrics (ios) ──────────────────────────────")
        print("cases: \(cases.count) (labeled \(labeled.count), known_miss \(misses.count))")
        print("local retention (labeled): \(retainedLocal.count)/\(labeled.count)")
        print("false local : \(falseLocal.count) \(falseLocal.map(\.id))")
        print("false cloud : \(falseCloud.count) \(falseCloud.map(\.id))")
        print("known_miss converted: \(converted.count)/\(misses.count) \(converted.map(\.id))")
        print("─────────────────────────────────────────────────────────────")

        let dump = decisions.keys.sorted().map { "\($0) \(decisions[$0]!)" }.joined(separator: "\n") + "\n"
        try dump.write(to: repoRoot.appendingPathComponent("tests/router/decisions-ios.txt"),
                       atomically: true, encoding: .utf8)
    }

    /// Any iOS/Android disagreement is always a bug — this converts the
    /// "keep in sync" comment into something mechanically enforced. Compares
    /// against Android's dumped decisions; skipped until the Android corpus
    /// test has been run at least once.
    func testCrossPlatformDecisions_agreeWithAndroidDump() throws {
        let androidURL = repoRoot.appendingPathComponent("tests/router/decisions-android.txt")
        guard FileManager.default.fileExists(atPath: androidURL.path) else {
            throw XCTSkip("Run the Android corpus tests first (missing decisions-android.txt)")
        }
        let android = try String(contentsOf: androidURL, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .reduce(into: [String: String]()) { result, line in
                let parts = line.split(separator: " ")
                guard parts.count == 2 else { return }
                result[String(parts[0])] = String(parts[1])
            }
        XCTAssertEqual(try allDecisions(), android, "iOS/Android routing divergence (always a bug)")
    }
}

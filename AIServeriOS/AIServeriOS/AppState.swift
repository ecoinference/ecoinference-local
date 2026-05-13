import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    // ── Server ────────────────────────────────────────────────────────────────

    @Published private(set) var serverRunning = false
    @Published private(set) var serverPort: UInt16

    // ── Model ─────────────────────────────────────────────────────────────────

    @Published private(set) var modelLoaded   = false
    @Published private(set) var loadedModelId: String?
    @Published private(set) var isLoading        = false
    @Published private(set) var loadError: String?
    /// Which model was being loaded when `loadError` was set.
    @Published private(set) var loadErrorModelId: String?

    // ── Download ──────────────────────────────────────────────────────────────

    @Published private(set) var downloadActive  = false
    @Published private(set) var downloadProgress: Double = 0   // 0–100
    @Published private(set) var downloadingModelId: String?
    @Published private(set) var downloadError: String?
    /// Which model was being downloaded when `downloadError` was set.
    @Published private(set) var downloadErrorModelId: String?

    // ── Catalog ───────────────────────────────────────────────────────────────

    @Published private(set) var models: [ModelInfo] = []

    // ── Private ───────────────────────────────────────────────────────────────

    private let settings  = SettingsService.shared
    private let server    = HttpServer()
    private let inference = InferenceService.shared
    private let download  = DownloadService.shared

    private init() {
        serverPort = settings.serverPort
        refreshCatalog()
        registerRoutes()
        wireServerCallbacks()
    }

    // MARK: - Server control

    private func wireServerCallbacks() {
        server.onStateChange = { [weak self] newState in
            // NWListener fires on a background queue; hop to MainActor.
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch newState {
                case .running:
                    self.serverRunning = true
                case .stopped, .error:
                    self.serverRunning = false
                case .starting:
                    break
                }
            }
        }
    }

    func startServer() {
        guard !serverRunning else { return }
        server.port = settings.serverPort
        serverPort  = settings.serverPort
        do {
            try server.start()
            activateAudioSession()   // keep NWListener alive in background
            // serverRunning is set to true by onStateChange when .ready fires.
        } catch {
            serverRunning = false
        }
    }

    func stopServer() {
        server.stop()
        deactivateAudioSession()
        // serverRunning is set to false by onStateChange(.stopped).
    }

    // ── Silent audio session (background keep-alive) ──────────────────────────
    // iOS suspends NWListener when the app is backgrounded unless the app holds
    // an active AVAudioSession with the UIBackgroundModes 'audio' entitlement.
    // A silent mixable session satisfies iOS without audible output.

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal — server still works in foreground
            print("[AppState] AVAudioSession activate failed: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false,
                options: .notifyOthersOnDeactivation)
        } catch {
            print("[AppState] AVAudioSession deactivate failed: \(error)")
        }
    }

    // MARK: - Catalog

    func refreshCatalog() {
        let loadedId = inference.loadedModelId
        models = ModelCatalog.all.map { info in
            var m = info
            m.downloaded = download.isDownloaded(m)
            m.loaded     = (m.id == loadedId)
            return m
        }
    }

    // MARK: - Download

    func startDownload(modelId: String) {
        guard let info = ModelCatalog.find(id: modelId) else { return }
        guard !downloadActive else { return }

        downloadActive        = true
        downloadProgress      = 0
        downloadingModelId    = modelId
        downloadError         = nil
        downloadErrorModelId  = nil

        // Capture service references and token on the MainActor before
        // entering the task, avoiding cross-actor property access.
        let downloadSvc = download
        let token       = settings.hfToken.isEmpty ? nil : settings.hfToken

        // download() is async (URLSession.bytes suspension points), so a
        // Task inheriting @MainActor is fine — it suspends without blocking.
        Task {
            do {
                try await downloadSvc.download(model: info, hfToken: token) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress * 100
                    }
                }
                downloadActive     = false
                downloadProgress   = 100
                downloadingModelId = nil
                refreshCatalog()
            } catch {
                downloadActive       = false
                downloadError        = error.localizedDescription
                downloadErrorModelId = modelId
                downloadingModelId   = nil
                refreshCatalog()
            }
        }
    }

    func cancelDownload() {
        download.cancel()
    }

    // MARK: - Model load / unload

    func loadModel(modelId: String, useGpu: Bool = false) {
        guard let info = ModelCatalog.find(id: modelId),
              download.isDownloaded(info) else { return }

        isLoading        = true
        loadError        = nil
        loadErrorModelId = nil

        // Capture service and path on the MainActor before entering the
        // detached task, so no @MainActor-isolated property is accessed
        // from a non-isolated context.
        let inferenceSvc = inference
        let modelPath    = download.filePath(for: info).path

        // inference.load() is blocking (5–30 s) — must run detached.
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try inferenceSvc.load(
                    modelId:      modelId,
                    modelPath:    modelPath,
                    useGpu:       useGpu,
                    maxNumTokens: 8192
                )
                await MainActor.run { [weak self] in
                    self?.modelLoaded       = true
                    self?.loadedModelId     = modelId
                    self?.isLoading         = false
                    self?.loadError         = nil
                    self?.loadErrorModelId  = nil
                    self?.refreshCatalog()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.loadError         = error.localizedDescription
                    self?.loadErrorModelId  = modelId
                    self?.isLoading         = false
                    self?.refreshCatalog()
                }
            }
        }
    }

    func unloadModel() {
        inference.unload()
        modelLoaded      = false
        loadedModelId    = nil
        loadError        = nil
        loadErrorModelId = nil
        refreshCatalog()
    }

    // MARK: - Route wiring

    private func registerRoutes() {
        let router = server.router
        registerHealthRoutes(router: router)
        registerCatalogRoutes(router: router)
        registerModelRoutes(router: router)
        registerDownloadRoutes(router: router)
        registerInferenceRoutes(router: router)
    }
}

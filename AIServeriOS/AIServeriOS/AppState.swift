import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    // ── Server ────────────────────────────────────────────────────────────────

    @Published private(set) var serverRunning = false
    @Published private(set) var serverPort: UInt16

    // ── Model ─────────────────────────────────────────────────────────────────

    @Published private(set) var modelLoaded   = false
    @Published private(set) var loadedModelId: String?
    @Published private(set) var isLoading     = false
    @Published private(set) var loadError: String?

    // ── Download ──────────────────────────────────────────────────────────────

    @Published private(set) var downloadActive  = false
    @Published private(set) var downloadProgress: Double = 0   // 0–100
    @Published private(set) var downloadingModelId: String?
    @Published private(set) var downloadError: String?

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
    }

    // MARK: - Server control

    func startServer() {
        guard !serverRunning else { return }
        server.port = settings.serverPort
        do {
            try server.start()
            serverRunning = true
            serverPort    = settings.serverPort
        } catch {
            serverRunning = false
        }
    }

    func stopServer() {
        server.stop()
        serverRunning = false
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

        downloadActive     = true
        downloadProgress   = 0
        downloadingModelId = modelId
        downloadError      = nil

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let token = self.settings.hfToken
            do {
                try await self.download.download(model: info, hfToken: token.isEmpty ? nil : token) { progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress * 100
                    }
                }
                await MainActor.run { [weak self] in
                    self?.downloadActive     = false
                    self?.downloadProgress   = 100
                    self?.downloadingModelId = nil
                    self?.refreshCatalog()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.downloadActive     = false
                    self?.downloadError      = error.localizedDescription
                    self?.downloadingModelId = nil
                    self?.refreshCatalog()
                }
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

        isLoading = true
        loadError = nil

        let modelPath = download.filePath(for: info).path

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try self.inference.load(
                    modelId:   modelId,
                    modelPath: modelPath,
                    useGpu:    useGpu,
                    maxTokens: 1024
                )
                await MainActor.run { [weak self] in
                    self?.modelLoaded   = true
                    self?.loadedModelId = modelId
                    self?.isLoading     = false
                    self?.refreshCatalog()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.loadError   = error.localizedDescription
                    self?.isLoading   = false
                    self?.refreshCatalog()
                }
            }
        }
    }

    func unloadModel() {
        inference.unload()
        modelLoaded   = false
        loadedModelId = nil
        refreshCatalog()
    }

    // MARK: - Route wiring

    private func registerRoutes() {
        let router = server.router
        registerHealthRoutes(router: router, port: settings.serverPort)
        registerCatalogRoutes(router: router)
        registerModelRoutes(router: router)
        registerDownloadRoutes(router: router)
        registerInferenceRoutes(router: router)
    }
}

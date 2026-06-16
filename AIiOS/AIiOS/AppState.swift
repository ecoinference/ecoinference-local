import Foundation
import SwiftUI
import os.log

private let log = Logger(subsystem: "ai.ecoinference.app", category: "AppState")

// MARK: - Deep link actions

enum DeepLinkAction: Equatable {
    case openChat(prefill: String? = nil, autoSend: Bool = false, systemPrompt: String? = nil)
    case openModels
    case openSettings
    case loadModel(id: String)
    case backgroundInfer(prompt: String, callbackURL: URL?)
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    // ── Model ─────────────────────────────────────────────────────────────────

    @Published private(set) var modelLoaded        = false
    @Published private(set) var loadedModelId: String?
    @Published private(set) var isLoading          = false
    @Published private(set) var loadError: String?
    @Published private(set) var loadErrorModelId: String?
    /// True when the loaded model's bundle supports image attachment in the UI.
    /// Distinct from the model being in multimodal mode (supportsVision) — a model
    /// may use the Conversation API without supporting actual image payloads.
    @Published private(set) var imageInputEnabled  = false

    // ── Download ──────────────────────────────────────────────────────────────

    @Published private(set) var downloadActive       = false
    @Published private(set) var downloadProgress: Double = 0   // 0–100
    @Published private(set) var downloadingModelId: String?
    @Published private(set) var downloadError: String?
    @Published private(set) var downloadErrorModelId: String?

    // ── Catalog ───────────────────────────────────────────────────────────────

    @Published private(set) var models: [ModelInfo] = []

    // ── Navigation / deep link ────────────────────────────────────────────────

    /// Set by the URL scheme handler; views react with .onChange(of: deepLink).
    @Published var deepLink: DeepLinkAction? = nil

    // ── Private ───────────────────────────────────────────────────────────────

    private let settings  = SettingsService.shared
    private let inference = InferenceService.shared
    private let download  = DownloadService.shared

    private init() {
        refreshCatalog()
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
        imageInputEnabled = models.first(where: { $0.loaded })?.supportsImageInput ?? false
    }

    // MARK: - Download

    /// [authToken] is currently unused — model files are served unauthenticated from
    /// our own server. Kept so a future auth-locked server can pass a token through
    /// without changing this call site.
    func startDownload(modelId: String, authToken: String? = nil) {
        guard let info = ModelCatalog.find(id: modelId) else { return }
        guard !downloadActive else { return }

        downloadActive        = true
        downloadProgress      = 0
        downloadingModelId    = modelId
        downloadError         = nil
        downloadErrorModelId  = nil

        let downloadSvc = download

        Task {
            do {
                try await downloadSvc.download(model: info, authToken: authToken) { [weak self] progress in
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

    func deleteModel(modelId: String) {
        guard let info = ModelCatalog.find(id: modelId) else { return }
        try? FileManager.default.removeItem(at: download.filePath(for: info))
        refreshCatalog()
    }

    // MARK: - Model load / unload

    func loadModel(modelId: String, useGpu: Bool = false) {
        guard let info = ModelCatalog.find(id: modelId),
              download.isDownloaded(info) else { return }

        isLoading        = true
        loadError        = nil
        loadErrorModelId = nil

        let inferenceSvc = inference
        let modelPath    = download.filePath(for: info).path

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // flutter_gemma recommends 4096 tokens for multimodal models;
                // the vision KV-cache pushes memory usage high enough that 8192
                // causes litert_lm_engine_create to fail on device.
                try inferenceSvc.load(
                    modelId:             modelId,
                    modelPath:           modelPath,
                    useGpu:              useGpu,
                    maxNumTokens:        info.maxContextTokens,
                    multimodal:          info.supportsVision,
                    speculativeDecoding: info.supportsSpeculativeDecoding
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
        modelLoaded       = false
        loadedModelId     = nil
        loadError         = nil
        loadErrorModelId  = nil
        imageInputEnabled = false
        refreshCatalog()
    }
}

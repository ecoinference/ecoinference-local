import Foundation
import Combine

/// Persists user preferences via UserDefaults.
/// Conforms to ObservableObject so SwiftUI views can react to changes.
final class SettingsService: ObservableObject {

    static let shared = SettingsService()
    private init() {}

    private let defaults = UserDefaults.standard

    private enum Key {
        static let geminiApiKey    = "gemini_api_key"
        static let selectedModelId = "selected_model_id"
        static let useGpu          = "use_gpu"
        static let maxNumTokens    = "max_num_tokens"
        static let systemPrompt    = "system_prompt"
    }

    // ── Gemini API key (cloud tier of the LLM router) ───────────────────────────

    @Published var geminiApiKey: String = "" {
        didSet { defaults.set(geminiApiKey, forKey: Key.geminiApiKey) }
    }

    // ── Model settings ────────────────────────────────────────────────────────

    @Published var selectedModelId: String? = nil {
        didSet { defaults.set(selectedModelId, forKey: Key.selectedModelId) }
    }

    @Published var useGpu: Bool = false {
        didSet { defaults.set(useGpu, forKey: Key.useGpu) }
    }

    /// KV-cache budget (prompt + history + output). Clamped to 512–8192.
    @Published var maxNumTokens: Int = 8192 {
        didSet {
            let clamped = max(512, min(8192, maxNumTokens))
            if clamped != maxNumTokens { maxNumTokens = clamped; return }
            defaults.set(maxNumTokens, forKey: Key.maxNumTokens)
        }
    }

    /// Optional system prompt injected at the start of every conversation.
    @Published var systemPrompt: String? = nil {
        didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) }
    }

    // ── Initialise from persisted values ──────────────────────────────────────

    func load() {
        geminiApiKey    = defaults.string(forKey: Key.geminiApiKey) ?? ""

        selectedModelId = defaults.string(forKey: Key.selectedModelId)
        useGpu          = defaults.bool(forKey: Key.useGpu)
        let stored      = defaults.integer(forKey: Key.maxNumTokens)
        maxNumTokens    = stored > 0 ? stored : 8192
        systemPrompt    = defaults.string(forKey: Key.systemPrompt)
    }
}

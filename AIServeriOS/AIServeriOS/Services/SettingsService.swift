import Foundation

/// Persists user preferences via UserDefaults.
final class SettingsService {

    static let shared = SettingsService()
    private init() {}

    private let defaults = UserDefaults.standard

    private enum Key {
        static let serverPort       = "server_port"
        static let hfToken          = "hf_token"
        static let selectedModelId  = "selected_model_id"
        static let useGpu           = "use_gpu"
        static let autoStart        = "auto_start"
    }

    var serverPort: UInt16 {
        get { UInt16(defaults.integer(forKey: Key.serverPort).nonZero ?? 8080) }
        set { defaults.set(Int(newValue), forKey: Key.serverPort) }
    }

    var autoStart: Bool {
        get { defaults.bool(forKey: Key.autoStart) }
        set { defaults.set(newValue, forKey: Key.autoStart) }
    }

    var hfToken: String {
        get { defaults.string(forKey: Key.hfToken) ?? "" }
        set { defaults.set(newValue, forKey: Key.hfToken) }
    }

    var selectedModelId: String? {
        get { defaults.string(forKey: Key.selectedModelId) }
        set { defaults.set(newValue, forKey: Key.selectedModelId) }
    }

    var useGpu: Bool {
        get { defaults.bool(forKey: Key.useGpu) }
        set { defaults.set(newValue, forKey: Key.useGpu) }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

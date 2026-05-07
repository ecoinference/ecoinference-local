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
        get {
            // Return stored value if the user has explicitly set one.
            if let stored = defaults.string(forKey: Key.hfToken), !stored.isEmpty {
                return stored
            }
            // Fall back to the build-time default from Local.xcconfig → Info.plist.
            // This seeds the token without committing it to source control.
            let buildDefault = Bundle.main.object(forInfoDictionaryKey: "HFTokenDefault")
                as? String ?? ""
            // Ignore the unexpanded placeholder from builds without Local.xcconfig.
            return buildDefault.hasPrefix("hf_") ? buildDefault : ""
        }
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

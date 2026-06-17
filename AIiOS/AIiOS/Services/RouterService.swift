import Foundation
import FirebaseRemoteConfig

/// Decides whether a prompt should go to the on-device model or the cloud
/// (Gemini) backend. Pure decision logic — does not perform inference itself,
/// so call sites stay in control of how/when to actually dispatch.
///
/// Not @MainActor: callers that already hold MainActor-isolated state (like
/// AppState.imageInputEnabled) pass it in via `localSupportsImage` rather than
/// this service reaching across actors to fetch it itself.
final class RouterService: ObservableObject {

    static let shared = RouterService()

    enum Tier: String { case local, cloud }

    struct Decision {
        let tier:   Tier
        let reason: String
        let ruleId: String?
        let facts:  [String: FactValue]
    }

    @Published private(set) var ruleSet: RouterRuleSet

    private let engine = RuleEngine()
    private let remoteConfig = RemoteConfig.remoteConfig()

    /// Firebase Remote Config parameter holding the full rules JSON as a string.
    /// Set/update this in Firebase Console → Remote Config → Parameters.
    private static let remoteConfigKey = "router_rules"

    private init() {
        ruleSet = Self.loadBundledDefault()
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0     // no throttle in debug builds
        #else
        settings.minimumFetchInterval = 3600  // 1 hour in production
        #endif
        remoteConfig.configSettings = settings
    }

    /// Evaluates the rule set against the current prompt/conversation and
    /// returns which tier should handle it.
    func decide(
        prompt: String,
        history: [InferenceMessage] = [],
        hasImage: Bool = false,
        localSupportsImage: Bool = false
    ) -> Decision {
        var facts = RouterFactExtractor.extract(prompt: prompt, history: history, hasImage: hasImage)
        facts["localSupportsImage"] = .bool(localSupportsImage)

        let outcome = engine.decide(facts: facts, ruleSet: ruleSet)
        let tier = Tier(rawValue: outcome.decision) ?? .local
        return Decision(tier: tier, reason: outcome.reason, ruleId: outcome.ruleId, facts: facts)
    }

    // MARK: - Remote rule updates

    enum RefreshResult {
        case updated(newVersion: Int)
        case alreadyCurrent(version: Int)
        case noRemoteValue
        case error(String)
    }

    /// Checks Firebase Remote Config for a newer rule set than what's currently
    /// loaded and swaps it in if found. Returns a RefreshResult describing what
    /// happened — useful for manual test triggers in dev builds. Failures leave
    /// the current rule set in place.
    @discardableResult
    func refreshFromRemote() async -> RefreshResult {
        do {
            try await remoteConfig.fetchAndActivate()

            let raw = remoteConfig.configValue(forKey: Self.remoteConfigKey).stringValue
            guard !raw.isEmpty, let data = raw.data(using: .utf8) else {
                return .noRemoteValue
            }

            let remote = try JSONDecoder().decode(RouterRuleSet.self, from: data)
            if remote.version > ruleSet.version {
                await MainActor.run { ruleSet = remote }
                return .updated(newVersion: remote.version)
            } else {
                return .alreadyCurrent(version: ruleSet.version)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Rule set loading

    /// Loaded once at init from the bundled JSON; `refreshFromRemote()` may
    /// later replace this with a newer version fetched from Remote Config.
    private static func loadBundledDefault() -> RouterRuleSet {
        guard let url = Bundle.main.url(forResource: "default_router_rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(RouterRuleSet.self, from: data)
        else {
            // Never crash on a missing/malformed bundle resource — fail open to "always local".
            return RouterRuleSet(version: 0, rules: [], defaultDecision: "local")
        }
        return parsed
    }
}

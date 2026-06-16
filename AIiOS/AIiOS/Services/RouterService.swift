import Foundation

/// Decides whether a prompt should go to the on-device model or the cloud
/// (Gemini) backend. Pure decision logic — does not perform inference itself,
/// so call sites stay in control of how/when to actually dispatch.
@MainActor
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

    private init() {
        ruleSet = Self.loadBundledDefault()
    }

    /// Evaluates the rule set against the current prompt/conversation and
    /// returns which tier should handle it.
    func decide(prompt: String, history: [InferenceMessage] = [], hasImage: Bool = false) -> Decision {
        var facts = RouterFactExtractor.extract(prompt: prompt, history: history, hasImage: hasImage)
        facts["localSupportsImage"] = .bool(AppState.shared.imageInputEnabled)

        let outcome = engine.decide(facts: facts, ruleSet: ruleSet)
        let tier = Tier(rawValue: outcome.decision) ?? .local
        return Decision(tier: tier, reason: outcome.reason, ruleId: outcome.ruleId, facts: facts)
    }

    // MARK: - Rule set loading

    /// Loaded once at init from the bundled JSON. A later phase will check a
    /// remote source (Firebase Remote Config) for an updated rule set and
    /// replace `ruleSet` if a newer version is found — this is the seam for that.
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

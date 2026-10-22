import Foundation

/// Tier vocabulary for three-tier routing. `decision` is the rules-v3 string
/// (docs/ROUTING_THREE_TIER.md §3.1); `rank` is the tier order
/// on_device < self_hosted < cloud.
enum Tier: Int, CaseIterable, Comparable {
    case onDevice = 0
    case selfHosted = 1
    case cloud = 2

    var decision: String {
        switch self {
        case .onDevice:   return "on_device"
        case .selfHosted: return "self_hosted"
        case .cloud:      return "cloud"
        }
    }

    init?(decision: String) {
        guard let t = Tier.allCases.first(where: { $0.decision == decision }) else { return nil }
        self = t
    }

    static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum Reachability: String, Codable {
    case yes
    case no
    case unknown
}

/// One tier's live state: is it there, can it be reached, what can it do.
struct TierState {
    let configured: Bool
    let reachable: Reachability
    let vision: Bool
    let web: Bool
    /// In estimated-token units (see TierResolver.needsFrom).
    let contextLimit: Int
}

/// User policy: highest tier allowed, an optional forced tier, and the D4
/// setting that makes EVERY cloud send an offer.
struct ResolverPolicy {
    var ceiling: Tier = .cloud
    var pin: Tier? = nil
    var offerAllCloud: Bool = false
}

enum ResolverAction: String {
    case send
    case offer
}

struct ResolverResult: Equatable {
    let action: ResolverAction
    let tier: Tier
    let reason: String
    /// OFFER only: where the answer actually happens if the offer is declined.
    let fallbackTier: Tier?
    let fallbackReason: String?
}

/// Tier resolver for three-tier routing — docs/ROUTING_THREE_TIER.md §3.2.
///
/// Second of the two pure steps: the RuleEngine decides the MINIMUM tier a
/// prompt needs; the resolver picks the ACTUAL tier from availability,
/// capabilities and user policy. Pure Foundation only — compiles into the
/// standalone test target and mirrors Android TierResolver.kt exactly (reason
/// strings and all; the shared fixtures at tests/router/resolver_cases.json
/// enforce it).
///
/// Decision semantics (D4): cloud is automatic only when the RULES asked for
/// it; a resolver that lands above the rules' tier at cloud produces an OFFER
/// with a degraded fallback, never an automatic send. Capability upgrades to
/// self-hosted are sends — it is still the user's own hardware (D3). Unknown
/// reachability never blocks a send; reachability comes from cached background
/// probes, never the send path.
enum TierResolver {

    // Reason strings are part of the cross-platform contract — fixtures pin
    // them byte-for-byte. Change here = change in TierResolver.kt + fixtures.
    static let reasonPinned = "Pinned by user."
    static let reasonUp = "Resolved to a higher tier: the minimum tier lacks a required capability."
    static let reasonDegraded =
        "No available tier meets this prompt's needs; answered on the most private reachable tier."
    static let offerEscalation = "Cloud escalation beyond the rules' tier is offered, never automatic."
    static let offerSetting = "Every cloud send is an offer under the user's escalation setting."

    /// v1 token estimate: prompt words plus a fixed budget per prior turn.
    /// Deliberately crude; must stay identical on Android.
    private static let tokensPerTurn = 100

    struct Needs {
        let vision: Bool
        let web: Bool
        let estimatedTokens: Int
    }

    static func needsFrom(_ facts: [String: FactValue]) -> Needs {
        let words: Int = { if case .int(let v)? = facts["wordCount"] { return v }; return 0 }()
        let turns: Int = { if case .int(let v)? = facts["conversationTurns"] { return v }; return 0 }()
        return Needs(
            vision: facts["hasImage"] == .bool(true),
            web: facts["mentionsCurrentEvents"] == .bool(true),
            estimatedTokens: words + turns * tokensPerTurn
        )
    }

    static func resolve(
        minTier: Tier,
        ruleReason: String,
        facts: [String: FactValue],
        tiers: [Tier: TierState],
        policy: ResolverPolicy
    ) -> ResolverResult {
        // 1. Pin wins — mirrors Remote's "Use only this server". Needs are not
        //    checked: pinning is an explicit user choice, failures surface as errors.
        if let pin = policy.pin, usable(tiers[pin]) {
            return send(pin, reasonPinned)
        }

        // 2-3. Lowest candidate at/above minTier, at/below ceiling, usable, capable.
        let needs = needsFrom(facts)
        let candidate = Tier.allCases
            .filter {
                $0 >= minTier && $0 <= policy.ceiling &&
                    usable(tiers[$0]) && meets(needs, tiers[$0])
            }
            .min(by: { $0.rawValue < $1.rawValue })

        if let candidate {
            // 4a. Cloud is gated: automatic only when the rules asked for it,
            //     unless the user's setting makes every cloud send an offer.
            if candidate == .cloud && (minTier != .cloud || policy.offerAllCloud) {
                let offerReason = minTier != .cloud ? offerEscalation : offerSetting
                let fallback = degradeTarget(tiers, policy, below: .cloud)
                return ResolverResult(
                    action: .offer, tier: .cloud, reason: offerReason,
                    fallbackTier: fallback, fallbackReason: reasonDegraded)
            }
            return send(candidate, candidate == minTier ? ruleReason : reasonUp)
        }

        // 4b. Nothing qualifies — degrade downward to the most private usable
        //     tier with a visible reason; on-device is the last resort.
        return send(degradeTarget(tiers, policy, below: nil), reasonDegraded)
    }

    private static func usable(_ state: TierState?) -> Bool {
        guard let state else { return false }
        return state.configured && state.reachable != .no
    }

    private static func meets(_ needs: Needs, _ state: TierState?) -> Bool {
        guard let state else { return false }
        if needs.vision && !state.vision { return false }
        if needs.web && !state.web { return false }
        return state.contextLimit >= needs.estimatedTokens
    }

    private static func degradeTarget(_ tiers: [Tier: TierState], _ policy: ResolverPolicy, below: Tier?) -> Tier {
        Tier.allCases
            .filter {
                $0 <= policy.ceiling &&
                    (below == nil || $0 < below!) &&
                    usable(tiers[$0])
            }
            .min(by: { $0.rawValue < $1.rawValue })
            ?? .onDevice
    }

    private static func send(_ tier: Tier, _ reason: String) -> ResolverResult {
        ResolverResult(action: .send, tier: tier, reason: reason, fallbackTier: nil, fallbackReason: nil)
    }
}

package ai.ecoinference.app.router

/**
 * Tier resolver for three-tier routing — docs/ROUTING_THREE_TIER.md §3.2.
 *
 * Second of the two pure steps: the RuleEngine decides the MINIMUM tier a
 * prompt needs; the resolver picks the ACTUAL tier from availability,
 * capabilities and user policy. No platform imports — runs on the plain JVM
 * test runner and mirrors iOS TierResolver.swift exactly (reason strings and
 * all; the shared fixtures at tests/router/resolver_cases.json enforce it).
 *
 * Decision semantics (D4): cloud is automatic only when the RULES asked for
 * it; a resolver that lands above the rules' tier at cloud produces an OFFER
 * with a degraded fallback, never an automatic send. Capability upgrades to
 * self-hosted are sends — it is still the user's own hardware (D3). Unknown
 * reachability never blocks a send; reachability comes from cached background
 * probes, never the send path.
 */

enum class Tier(val rank: Int, val decision: String) {
    ON_DEVICE(0, "on_device"),
    SELF_HOSTED(1, "self_hosted"),
    CLOUD(2, "cloud");

    companion object {
        fun fromDecision(value: String): Tier? = values().firstOrNull { it.decision == value }
    }
}

enum class Reachability { YES, NO, UNKNOWN }

/** One tier's live state: is it there, can it be reached, what can it do. */
data class TierState(
    val configured: Boolean,
    val reachable: Reachability,
    val vision: Boolean,
    val web: Boolean,
    /** In estimated-token units (see [TierResolver.needsFrom]). */
    val contextLimit: Int,
)

/** User policy: highest tier allowed, an optional forced tier, and the D4
 *  setting that makes EVERY cloud send an offer. */
data class ResolverPolicy(
    val ceiling: Tier = Tier.CLOUD,
    val pin: Tier? = null,
    val offerAllCloud: Boolean = false,
)

enum class ResolverAction { SEND, OFFER }

data class ResolverResult(
    val action: ResolverAction,
    val tier: Tier,
    val reason: String,
    /** OFFER only: where the answer actually happens if the offer is declined. */
    val fallbackTier: Tier? = null,
    val fallbackReason: String? = null,
)

object TierResolver {

    // Reason strings are part of the cross-platform contract — fixtures pin
    // them byte-for-byte. Change here = change in TierResolver.swift + fixtures.
    const val REASON_PINNED = "Pinned by user."
    const val REASON_UP = "Resolved to a higher tier: the minimum tier lacks a required capability."
    const val REASON_DEGRADED =
        "No available tier meets this prompt's needs; answered on the most private reachable tier."
    const val OFFER_ESCALATION = "Cloud escalation beyond the rules' tier is offered, never automatic."
    const val OFFER_SETTING = "Every cloud send is an offer under the user's escalation setting."

    /** v1 token estimate: prompt words plus a fixed budget per prior turn.
     *  Deliberately crude; must stay identical on iOS. */
    private const val TOKENS_PER_TURN = 100

    data class Needs(val vision: Boolean, val web: Boolean, val estimatedTokens: Int)

    fun needsFrom(facts: Map<String, FactValue>): Needs {
        val words = (facts["wordCount"] as? FactValue.IntValue)?.value ?: 0
        val turns = (facts["conversationTurns"] as? FactValue.IntValue)?.value ?: 0
        return Needs(
            vision = facts["hasImage"] == FactValue.BoolValue(true),
            web = facts["mentionsCurrentEvents"] == FactValue.BoolValue(true),
            estimatedTokens = words + turns * TOKENS_PER_TURN,
        )
    }

    fun resolve(
        minTier: Tier,
        ruleReason: String,
        facts: Map<String, FactValue>,
        tiers: Map<Tier, TierState>,
        policy: ResolverPolicy,
    ): ResolverResult {
        // 1. Pin wins — mirrors Remote's "Use only this server". Needs are not
        //    checked: pinning is an explicit user choice, failures surface as errors.
        policy.pin?.let { pin ->
            if (usable(tiers[pin])) return send(pin, REASON_PINNED)
        }

        // 2-3. Lowest candidate at/above minTier, at/below ceiling, usable, capable.
        val needs = needsFrom(facts)
        val candidate = Tier.values()
            .filter {
                it.rank >= minTier.rank && it.rank <= policy.ceiling.rank &&
                    usable(tiers[it]) && meets(needs, tiers[it])
            }
            .minByOrNull { it.rank }

        if (candidate != null) {
            // 4a. Cloud is gated: automatic only when the rules asked for it,
            //     unless the user's setting makes every cloud send an offer.
            if (candidate == Tier.CLOUD && (minTier != Tier.CLOUD || policy.offerAllCloud)) {
                val offerReason =
                    if (minTier != Tier.CLOUD) OFFER_ESCALATION else OFFER_SETTING
                val fallback = degradeTarget(tiers, policy, below = Tier.CLOUD)
                return ResolverResult(
                    ResolverAction.OFFER, Tier.CLOUD, offerReason, fallback, REASON_DEGRADED
                )
            }
            return send(candidate, if (candidate == minTier) ruleReason else REASON_UP)
        }

        // 4b. Nothing qualifies — degrade downward to the most private usable
        //     tier with a visible reason; on-device is the last resort.
        return send(degradeTarget(tiers, policy, below = null), REASON_DEGRADED)
    }

    private fun usable(state: TierState?): Boolean =
        state != null && state.configured && state.reachable != Reachability.NO

    private fun meets(needs: Needs, state: TierState?): Boolean {
        if (state == null) return false
        if (needs.vision && !state.vision) return false
        if (needs.web && !state.web) return false
        return state.contextLimit >= needs.estimatedTokens
    }

    private fun degradeTarget(tiers: Map<Tier, TierState>, policy: ResolverPolicy, below: Tier?): Tier =
        Tier.values()
            .filter {
                it.rank <= policy.ceiling.rank &&
                    (below == null || it.rank < below.rank) &&
                    usable(tiers[it])
            }
            .minByOrNull { it.rank }
            ?: Tier.ON_DEVICE

    private fun send(tier: Tier, reason: String) = ResolverResult(ResolverAction.SEND, tier, reason)
}

package ai.ecoinference.app.router

import ai.ecoinference.app.inference.InferenceMessage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Corpus-driven router tests — plain JVM, no device. Mirrors iOS's
 * RouterCorpusTests.swift; both read the *same* corpus at
 * `tests/router/corpus.jsonl`. Design and rationale: docs/ROUTING.md §2.
 *
 * Three layers:
 * 1. Every case not flagged `known_miss` must route as labeled — a hard failure.
 * 2. `known_miss` cases are evaluated and reported but never fail the build;
 *    the count that now route correctly ("conversion") is the instrument that
 *    decides whether a semantic-fact replacement earns its cost.
 * 3. Both platforms dump per-case decisions to `tests/router/decisions-*.txt`;
 *    when both dumps exist, they are compared line-by-line. Any divergence is
 *    always a bug — this mechanically enforces the "keep in sync" comment.
 */
class RouterCorpusTest {

    @Serializable
    private data class CaseContext(
        val turns: Int = 0,
        val hasImage: Boolean = false,
        val localSupportsImage: Boolean = true,
    )

    @Serializable
    private data class PolicySpec(
        val ceiling: String? = null,
        val pin: String? = null,
        val offerAllCloud: Boolean = false,
    )

    @Serializable
    private data class CorpusCase(
        val id: String,
        val prompt: String,
        val expect: String,
        val because: String = "",
        val context: CaseContext = CaseContext(),
        val notes: String = "",
        @SerialName("known_miss") val knownMiss: Boolean = false,
        // ── Three-tier fields (docs/ROUTING_THREE_TIER.md §6) ──
        @SerialName("expect_min_tier") val expectMinTier: String = "",
        @SerialName("expect_tier") val expectTier: String = "",
        @SerialName("expect_action") val expectAction: String = "send",
        @SerialName("expect_fallback_tier") val expectFallbackTier: String? = null,
        /** Per-tier availability shorthand: ok | down | absent | no_web | no_vision. */
        val availability: Map<String, String> = emptyMap(),
        val policy: PolicySpec? = null,
    )

    private val json = Json { ignoreUnknownKeys = true }

    /** Walks up from the test JVM's working dir until the shared corpus is found. */
    private fun repoRoot(): File {
        val cwd = System.getProperty("user.dir") ?: error("user.dir system property unavailable")
        var dir = File(cwd).absoluteFile
        while (!File(dir, "tests/router/corpus.jsonl").isFile) {
            dir = dir.parentFile
                ?: error("tests/router/corpus.jsonl not found at or above $cwd")
        }
        return dir
    }

    private fun loadCases(): List<CorpusCase> =
        File(repoRoot(), "tests/router/corpus.jsonl")
            .readLines()
            .filter { it.isNotBlank() }
            .map { json.decodeFromString(CorpusCase.serializer(), it) }

    private fun loadRuleSet(): RouterRuleSet =
        json.decodeFromString(
            RouterRuleSet.serializer(),
            File(repoRoot(), "AIAndroid/app/src/main/assets/default_router_rules.json").readText(),
        )

    /** Mirrors RouterService.decide() minus Firebase: same facts, same engine. */
    private fun decide(case: CorpusCase, ruleSet: RouterRuleSet): RuleOutcome {
        val history = List(case.context.turns) { InferenceMessage(role = "user", text = "turn $it") }
        val facts = RouterFactExtractor.extract(case.prompt, history, case.context.hasImage)
        facts["localSupportsImage"] = FactValue.BoolValue(case.context.localSupportsImage)
        return RuleEngine.decide(facts, ruleSet)
    }

    @Test
    fun corpusCases_withoutKnownMiss_routeAsExpected() {
        val ruleSet = loadRuleSet()
        val failures = loadCases()
            .filterNot { it.knownMiss }
            .map { case ->
                val outcome = decide(case, ruleSet)
                if (outcome.decision == case.expect) {
                    null
                } else {
                    "${case.id}: expected ${case.expect}, got ${outcome.decision} " +
                        "(rule=${outcome.ruleId ?: "default"}) — ${case.because}"
                }
            }
            .filterNotNull()
        assertTrue(
            "Router misrouted ${failures.size} labeled corpus case(s):\n" + failures.joinToString("\n"),
            failures.isEmpty(),
        )
    }

    /**
     * Reports the four metrics from docs/ROUTING.md §2 and dumps this platform's
     * decisions for the cross-platform comparison. Never fails — known_miss cases
     * are *expected* to be wrong until a semantic replacement lands.
     */
    @Test
    fun corpusMetrics_reportAndDumpDecisions() {
        val ruleSet = loadRuleSet()
        val cases = loadCases()

        val decisions = cases.associate { it.id to decide(it, ruleSet).decision }

        val labeled = cases.filterNot { it.knownMiss }
        val misses = cases.filter { it.knownMiss }
        val falseLocal = labeled.filter { it.expect == "cloud" && decisions[it.id] == "local" }
        val falseCloud = labeled.filter { it.expect == "local" && decisions[it.id] == "cloud" }
        val retainedLocal = labeled.count { decisions[it.id] == "local" }
        val converted = misses.filter { decisions[it.id] == it.expect }

        println("── router corpus metrics (android) ──────────────────────────")
        println("cases: ${cases.size} (labeled ${labeled.size}, known_miss ${misses.size})")
        println("local retention (labeled): $retainedLocal/${labeled.size}")
        println("false local : ${falseLocal.size} ${falseLocal.map { it.id }}")
        println("false cloud : ${falseCloud.size} ${falseCloud.map { it.id }}")
        println("known_miss converted: ${converted.size}/${misses.size} ${converted.map { it.id }}")
        println("─────────────────────────────────────────────────────────────")

        File(repoRoot(), "tests/router/decisions-android.txt").writeText(
            decisions.toSortedMap().entries.joinToString("\n") { "${it.key} ${it.value}" } + "\n"
        )
    }

    /**
     * Any iOS/Android disagreement is always a bug — this converts the
     * "keep in sync" comment into something mechanically enforced. Compares
     * freshly computed Android decisions against iOS's dump, so the test is
     * independent of method execution order; skipped until the iOS corpus
     * test has been run at least once.
     */
    @Test
    fun crossPlatformDecisions_agreeWithIosDump() {
        val ios = File(repoRoot(), "tests/router/decisions-ios.txt")
        assumeTrue("Run the iOS corpus tests first (missing ${ios.path})", ios.isFile)
        val ruleSet = loadRuleSet()
        val android = loadCases().associate { it.id to decide(it, ruleSet).decision }
        val iosDecisions = ios.readLines()
            .filter { it.isNotBlank() }
            .associate { val parts = it.split(" "); parts[0] to parts[1] }
        assertEquals("iOS/Android routing divergence (always a bug)", iosDecisions, android)
    }

    // ── Three-tier pipeline: rules v3 → minTier → TierResolver ─────────────
    // docs/ROUTING_THREE_TIER.md §6. Same standard profile and availability
    // shorthand on both platforms — the v3 parity dump enforces it.

    private fun loadRuleSetV3(): RouterRuleSet =
        json.decodeFromString(
            RouterRuleSet.serializer(),
            File(repoRoot(), "AIAndroid/app/src/main/assets/default_router_rules_v3.json").readText(),
        )

    /** Standard capability profile; on-device vision comes from the case's
     *  localSupportsImage (that fact IS the on-device tier's vision capability
     *  under v3 — the image rule moved into the resolver, §3.3). */
    private fun tiersFor(case: CorpusCase): Map<Tier, TierState> {
        val base = mapOf(
            Tier.ON_DEVICE to TierState(true, Reachability.YES, case.context.localSupportsImage, false, 2_000),
            Tier.SELF_HOSTED to TierState(true, Reachability.YES, vision = true, web = true, contextLimit = 32_000),
            Tier.CLOUD to TierState(true, Reachability.YES, vision = true, web = true, contextLimit = 1_000_000),
        )
        return base.mapValues { (tier, state) ->
            when (case.availability[tier.decision] ?: "ok") {
                "ok"       -> state
                "down"     -> state.copy(reachable = Reachability.NO)
                "absent"   -> state.copy(configured = false)
                "no_web"   -> state.copy(web = false)
                "no_vision"-> state.copy(vision = false)
                else -> error("${case.id}: unknown availability shorthand ${case.availability[tier.decision]}")
            }
        }
    }

    private fun policyFor(case: CorpusCase): ResolverPolicy {
        val p = case.policy ?: return ResolverPolicy()
        return ResolverPolicy(
            ceiling = p.ceiling?.let { Tier.fromDecision(it) ?: error("${case.id}: bad ceiling $it") } ?: Tier.CLOUD,
            pin = p.pin?.let { Tier.fromDecision(it) ?: error("${case.id}: bad pin $it") },
            offerAllCloud = p.offerAllCloud,
        )
    }

    private data class V3Outcome(
        val minTier: Tier,
        val ruleId: String?,
        val result: ResolverResult,
    )

    private fun runV3(case: CorpusCase, ruleSet: RouterRuleSet, factsOf: (CorpusCase) -> Map<String, FactValue>): V3Outcome {
        val facts = factsOf(case)
        val outcome = RuleEngine.decide(facts, ruleSet)
        val minTier = Tier.fromDecision(outcome.decision)
            ?: error("${case.id}: v3 rules produced non-tier decision '${outcome.decision}'")
        val result = TierResolver.resolve(minTier, outcome.reason, facts, tiersFor(case), policyFor(case))
        return V3Outcome(minTier, outcome.ruleId, result)
    }

    private fun factsFor(case: CorpusCase): Map<String, FactValue> {
        val history = List(case.context.turns) { InferenceMessage(role = "user", text = "turn $it") }
        val facts = RouterFactExtractor.extract(case.prompt, history, case.context.hasImage)
        facts["localSupportsImage"] = FactValue.BoolValue(case.context.localSupportsImage)
        return facts
    }

    /** Dump line: "id minTier action tier fallback" — fallback is "-" for sends. */
    private fun v3Line(id: String, o: V3Outcome): String =
        "$id ${o.minTier.decision} ${o.result.action.name.lowercase()} ${o.result.tier.decision} " +
            (o.result.fallbackTier?.decision ?: "-")

    private fun v3Matches(o: V3Outcome, case: CorpusCase): Boolean =
        o.minTier.decision == case.expectMinTier &&
            o.result.action.name.lowercase() == case.expectAction &&
            o.result.tier.decision == case.expectTier &&
            o.result.fallbackTier?.decision == case.expectFallbackTier

    @Test
    fun v3CorpusCases_withoutKnownMiss_routeAsExpected() {
        val ruleSet = loadRuleSetV3()
        val failures = loadCases()
            .filterNot { it.knownMiss }
            .map { case ->
                val o = runV3(case, ruleSet, ::factsFor)
                if (v3Matches(o, case)) {
                    null
                } else {
                    "${case.id}: expected (${case.expectMinTier}, ${case.expectAction}, ${case.expectTier}, " +
                        "${case.expectFallbackTier ?: "-"}), got (${o.minTier.decision}, " +
                        "${o.result.action.name.lowercase()}, ${o.result.tier.decision}, " +
                        "${o.result.fallbackTier?.decision ?: "-"}) (rule=${o.ruleId ?: "default"}) — ${case.because}"
                }
            }
            .filterNotNull()
        assertTrue(
            "Three-tier pipeline misrouted ${failures.size} labeled corpus case(s):\n" + failures.joinToString("\n"),
            failures.isEmpty(),
        )
    }

    @Test
    fun v3CorpusMetrics_reportAndDumpDecisions() {
        val ruleSet = loadRuleSetV3()
        val cases = loadCases()
        val outcomes = cases.associate { it.id to runV3(it, ruleSet, ::factsFor) }

        val labeled = cases.filterNot { it.knownMiss }
        val misses = cases.filter { it.knownMiss }
        val labeledPass = labeled.filter { v3Matches(outcomes[it.id]!!, it) }
        val converted = misses.filter { v3Matches(outcomes[it.id]!!, it) }
        val sends = outcomes.values.count { it.result.action == ResolverAction.SEND }
        val cloudSends = outcomes.values.count {
            it.result.action == ResolverAction.SEND && it.result.tier == Tier.CLOUD
        }
        val offers = outcomes.values.count { it.result.action == ResolverAction.OFFER }

        println("── three-tier corpus metrics (android) ──────────────────────")
        println("cases: ${cases.size} (labeled ${labeled.size}, known_miss ${misses.size})")
        println("labeled passing (minTier,action,tier,fallback): ${labeledPass.size}/${labeled.size}")
        println("known_miss converted: ${converted.size}/${misses.size} ${converted.map { it.id }}")
        println("datacenter avoidance: sends $sends (cloud $cloudSends), offers $offers " +
            "(keyword facts only — embedder unavailable in JVM tests)")
        println("─────────────────────────────────────────────────────────────")

        File(repoRoot(), "tests/router/decisions-v3-android.txt").writeText(
            outcomes.toSortedMap().entries.joinToString("\n") { v3Line(it.key, it.value) } + "\n"
        )
    }

    @Test
    fun v3CrossPlatformDecisions_agreeWithIosDump() {
        val ios = File(repoRoot(), "tests/router/decisions-v3-ios.txt")
        assumeTrue("Run the iOS corpus tests first (missing ${ios.path})", ios.isFile)
        val ruleSet = loadRuleSetV3()
        val android = loadCases().associate { c ->
            val parts = v3Line(c.id, runV3(c, ruleSet, ::factsFor)).split(" ")
            parts[0] to parts.drop(1)
        }
        val iosDecisions = ios.readLines()
            .filter { it.isNotBlank() }
            .associate { val parts = it.split(" "); parts[0] to parts.drop(1) }
        assertEquals("iOS/Android three-tier divergence (always a bug)", iosDecisions, android)
    }
}

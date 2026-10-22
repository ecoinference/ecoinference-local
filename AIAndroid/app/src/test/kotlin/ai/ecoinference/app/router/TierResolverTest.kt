package ai.ecoinference.app.router

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * TierResolver against the shared fixtures at tests/router/resolver_cases.json —
 * the same file the iOS TierResolverTests.swift reads, so any iOS/Android
 * disagreement in resolution OR reason strings fails one of the two suites.
 * Also guards the rules-v3 vocabulary and the byte-identity of the bundled
 * default_router_rules_v3.json across platforms.
 */
class TierResolverTest {

    @Serializable
    private data class FixtureTierState(
        val configured: Boolean,
        val reachable: String,
        val vision: Boolean,
        val web: Boolean,
        val contextLimit: Int,
    )

    @Serializable
    private data class FixturePolicy(
        val ceiling: String,
        val pin: String?,
        val offerAllCloud: Boolean,
    )

    @Serializable
    private data class FixtureExpect(
        val action: String,
        val tier: String,
        val reason: String,
        val fallbackTier: String?,
        val fallbackReason: String?,
    )

    @Serializable
    private data class FixtureCase(
        val id: String,
        val minTier: String,
        val ruleReason: String,
        val facts: Map<String, FactValue>,
        val tiers: Map<String, FixtureTierState>,
        val policy: FixturePolicy,
        val expect: FixtureExpect,
    )

    @Serializable
    private data class FixtureFile(val cases: List<FixtureCase>)

    private val json = Json { ignoreUnknownKeys = true }

    private fun repoRoot(): File {
        val cwd = System.getProperty("user.dir") ?: error("user.dir system property unavailable")
        var dir = File(cwd).absoluteFile
        while (!File(dir, "tests/router/resolver_cases.json").isFile) {
            dir = dir.parentFile
                ?: error("tests/router/resolver_cases.json not found at or above $cwd")
        }
        return dir
    }

    private fun loadCases(): List<FixtureCase> =
        json.decodeFromString(
            FixtureFile.serializer(),
            File(repoRoot(), "tests/router/resolver_cases.json").readText()
        ).cases

    private fun reachability(s: String): Reachability = when (s) {
        "yes" -> Reachability.YES
        "no" -> Reachability.NO
        "unknown" -> Reachability.UNKNOWN
        else -> error("bad reachable value: $s")
    }

    private fun tier(decision: String): Tier =
        Tier.fromDecision(decision) ?: error("bad tier decision: $decision")

    @Test
    fun resolverCases_matchSharedFixtures() {
        for (case in loadCases()) {
            val tiers = case.tiers.entries.associate { entry ->
                tier(entry.key) to TierState(
                    configured = entry.value.configured,
                    reachable = reachability(entry.value.reachable),
                    vision = entry.value.vision,
                    web = entry.value.web,
                    contextLimit = entry.value.contextLimit,
                )
            }
            val policy = ResolverPolicy(
                ceiling = tier(case.policy.ceiling),
                pin = case.policy.pin?.let { tier(it) },
                offerAllCloud = case.policy.offerAllCloud,
            )
            val result = TierResolver.resolve(
                minTier = tier(case.minTier),
                ruleReason = case.ruleReason,
                facts = case.facts,
                tiers = tiers,
                policy = policy,
            )
            assertEquals("${case.id}: action", case.expect.action.uppercase(), result.action.name)
            assertEquals("${case.id}: tier", tier(case.expect.tier), result.tier)
            assertEquals("${case.id}: reason", case.expect.reason, result.reason)
            assertEquals(
                "${case.id}: fallbackTier",
                case.expect.fallbackTier?.let { tier(it) },
                result.fallbackTier
            )
            assertEquals("${case.id}: fallbackReason", case.expect.fallbackReason, result.fallbackReason)
        }
    }

    @Test
    fun rulesV3_useOnlyTierVocabulary() {
        val v3 = File(repoRoot(), "AIAndroid/app/src/main/assets/default_router_rules_v3.json")
        val ruleSet = json.decodeFromString(RouterRuleSet.serializer(), v3.readText())
        assertEquals(3, ruleSet.version)
        assertNotNull("defaultDecision not in v3 vocabulary", Tier.fromDecision(ruleSet.defaultDecision))
        assertEquals(Tier.ON_DEVICE, Tier.fromDecision(ruleSet.defaultDecision))
        for (rule in ruleSet.rules) {
            assertNotNull("${rule.id}: decision not in v3 vocabulary", Tier.fromDecision(rule.decision))
        }
        // §3.3: the vision capability check moved out of the rules file.
        assertTrue(ruleSet.rules.none { it.id == "image_unsupported_locally" })
        // D3: sensitive stays on user-owned hardware, never minTier cloud.
        val sensitive = ruleSet.rules.first { it.id == "sensitive_domain" }
        assertEquals(Tier.SELF_HOSTED, Tier.fromDecision(sensitive.decision))
    }

    @Test
    fun rulesV3_byteIdenticalAcrossPlatforms() {
        val android = File(repoRoot(), "AIAndroid/app/src/main/assets/default_router_rules_v3.json").readBytes()
        val ios = File(repoRoot(), "AIiOS/AIiOS/default_router_rules_v3.json").readBytes()
        assertTrue("default_router_rules_v3.json diverged between platforms", android.contentEquals(ios))
    }
}

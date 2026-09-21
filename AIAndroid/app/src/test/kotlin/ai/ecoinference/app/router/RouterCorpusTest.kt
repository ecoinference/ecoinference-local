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
    private data class CorpusCase(
        val id: String,
        val prompt: String,
        val expect: String,
        val because: String = "",
        val context: CaseContext = CaseContext(),
        val notes: String = "",
        @SerialName("known_miss") val knownMiss: Boolean = false,
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
}

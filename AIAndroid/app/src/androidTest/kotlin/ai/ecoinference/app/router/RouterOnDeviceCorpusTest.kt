package ai.ecoinference.app.router

import ai.ecoinference.app.inference.InferenceMessage
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * On-device router corpus run — the measurement the JVM harness structurally
 * cannot make: the REAL Needle engine, real embeddings, real latency
 * (docs/ROUTING.md §2/§4; the Mac-side probe said GO at 13/15, this is the
 * hardware confirmation). Reads the same shared corpus (tests/router/,
 * wired as androidTest assets) and the same bundled v2 rules the production
 * RouterService uses.
 *
 * Run: ./gradlew :app:connectedDebugAndroidTest   (device attached via adb)
 * Report prints to instrumentation stdout — captured in the connected
 * androidTest-results XML system-out under app/build/outputs.
 *
 * Hard-fails only on labeled regressions; known_miss conversion and latency
 * are reported (the conversion count is the instrument, not a gate — the
 * Mac measurement is the GO record).
 */
@RunWith(AndroidJUnit4::class)
class RouterOnDeviceCorpusTest {

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
        val context: CaseContext = CaseContext(),
        @SerialName("known_miss") val knownMiss: Boolean = false,
        val holdout: Boolean = false,
    )

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun corpusThroughRealNeedleEngine() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext

        val cases = instrumentation.context.assets.open("corpus.jsonl")
            .bufferedReader().use { it.readText() }
            .lines().filter { it.isNotBlank() }
            .map { json.decodeFromString(CorpusCase.serializer(), it) }
        val ruleSet = appContext.assets.open("default_router_rules.json")
            .bufferedReader().use { it.readText() }
            .let { json.decodeFromString(RouterRuleSet.serializer(), it) }

        // EcoInferenceApp.onCreate already called NeedleEmbedder.start() when
        // instrumentation created the Application — just wait for readiness.
        val deadline = System.currentTimeMillis() + 90_000
        while (!NeedleEmbedder.isAvailable() && System.currentTimeMillis() < deadline) {
            Thread.sleep(250)
        }
        assertTrue("Needle engine not ready within 90 s on device", NeedleEmbedder.isAvailable())

        var regressions = 0
        var converted = 0
        var convertedTuning = 0
        var misses = 0
        var missesTuning = 0
        val latencies = mutableListOf<Long>()
        val failures = mutableListOf<String>()
        val convertedIds = mutableListOf<String>()

        for (case in cases) {
            val history = List(case.context.turns) {
                InferenceMessage(role = "user", text = "turn $it")
            }
            val facts = RouterFactExtractor.extract(case.prompt, history, case.context.hasImage)
            facts["localSupportsImage"] = FactValue.BoolValue(case.context.localSupportsImage)

            val t0 = System.nanoTime()
            val semantic = NeedleEmbedder.semanticFacts(case.prompt)
            latencies += (System.nanoTime() - t0) / 1_000_000
            assertNotNull("${case.id}: semanticFacts null with engine available", semantic)
            facts.putAll(semantic!!)

            val decision = RuleEngine.decide(facts, ruleSet).decision
            if (case.knownMiss) {
                misses++
                if (!case.holdout) missesTuning++
                if (decision == case.expect) {
                    converted++
                    if (!case.holdout) convertedTuning++
                    convertedIds += case.id
                }
            } else if (decision != case.expect) {
                regressions++
                failures += "${case.id}: expected ${case.expect}, got $decision"
            }
        }

        latencies.sort()
        println("── on-device corpus run (${Build.MODEL}, API ${Build.VERSION.SDK_INT}) ──")
        println("cases: ${cases.size} | labeled regressions: $regressions $failures")
        println("known_miss converted: $converted/$misses " +
            "(tuning split $convertedTuning/$missesTuning) $convertedIds")
        println("embed latency ms: min ${latencies.first()} " +
            "median ${latencies[latencies.size / 2]} max ${latencies.last()}")
        println("─────────────────────────────────────────────────────────────")
        assertEquals("labeled regressions on device: $failures", 0, regressions)
    }
}

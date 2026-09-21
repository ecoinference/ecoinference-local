package ai.ecoinference.app.router

import android.content.Context
import android.util.Log
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.concurrent.Executors

/**
 * Cactus Needle 3 as a fixed feature extractor for the router's semantic
 * facts (docs/ROUTING.md §4 — adopted design). The model ships once; ALL
 * tunable intelligence (exemplar texts, thresholds, centering mean) lives in
 * [ExemplarConfig] JSON — bundled default plus live updates via Firebase
 * Remote Config key `router_exemplars`, same version-gated pattern as
 * `router_rules`. Mirrors iOS NeedleEmbedder.swift.
 *
 * Failure contract: every failure path leaves [semanticFacts] returning null
 * and the router falls back to keyword facts. Routing must never block or
 * crash chat. Engine unavailable (stub ABI, missing weights, init error) is a
 * normal state, not an error.
 *
 * Threading: the needle C API is one process-global, NOT thread-safe model.
 * Every native call runs on [executor]; callers may invoke [semanticFacts]
 * from any thread except the executor itself (it blocks on submit().get()).
 */
object NeedleEmbedder {

    private const val TAG = "NeedleEmbedder"

    @Serializable
    data class ExemplarConfig(
        val version: Int,
        /** fact name -> exemplar texts (embedded once per config load). */
        val categories: Map<String, List<String>>,
        /** fact name -> strict-greater max-cosine threshold. */
        val thresholds: Map<String, Double>,
        /** Fixed centering mean, dim must match the model (3072). Null = no centering. */
        val mean: List<Double>? = null,
    )

    private val json = Json { ignoreUnknownKeys = true }
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "needle-embedder").apply { isDaemon = true }
    }

    @Volatile private var ready = false
    @Volatile private var dim = 0

    // Guarded by executor: mutated only in tasks running on it.
    private var config: ExemplarConfig? = null
    private var mean: FloatArray? = null
    private var exemplars: Map<String, List<FloatArray>> = emptyMap()

    private external fun nativeLoad(cact: ByteArray): Int
    private external fun nativeEmbed(text: String, out: FloatArray): Int
    private external fun nativeLastError(): String
    @Suppress("unused") private external fun nativeReset()

    /** Fire-and-forget engine + bundled-config startup; call once from Application.onCreate. */
    fun start(context: Context) {
        val appContext = context.applicationContext
        executor.execute {
            try {
                initOnExecutor(appContext)
            } catch (t: Throwable) {
                // UnsatisfiedLinkError (stub ABI), missing asset, native failure —
                // all mean "embedder unavailable", and keyword facts carry on.
                Log.i(TAG, "embedder unavailable: ${t.message}")
            }
        }
    }

    /** Version-gated live update (Remote Config `router_exemplars`). */
    fun applyConfigIfNewer(newConfig: ExemplarConfig) {
        executor.execute {
            if (newConfig.version > (config?.version ?: 0)) {
                applyConfigOnExecutor(newConfig)
            }
        }
    }

    /**
     * Semantic facts for one prompt, or null when the embedder is unavailable
     * or anything goes wrong — callers keep their keyword-derived facts.
     * ~8-10 ms per prompt on M-series Macs; the Lenovo TB336FU measurement is
     * still owed (ROUTING.md §4 item 2).
     */
    fun semanticFacts(prompt: String): Map<String, FactValue>? {
        if (!ready) return null
        return try {
            executor.submit<Map<String, FactValue>?> {
                val c = config ?: return@submit null
                val vec = embedOnExecutor(ExemplarScorer.normalize(prompt)) ?: return@submit null
                ExemplarScorer.semanticFacts(vec, mean, exemplars, c.thresholds)
            }.get()
        } catch (t: Throwable) {
            Log.w(TAG, "semanticFacts failed, failing open: ${t.message}")
            null
        }
    }

    // ── executor-thread internals ──────────────────────────────────────────

    private fun initOnExecutor(context: Context) {
        System.loadLibrary("needle_jni")
        val cact = context.assets.open("needle3.cact").use { it.readBytes() }
        val d = nativeLoad(cact)
        if (d <= 0) {
            Log.i(TAG, "nativeLoad failed ($d): ${nativeLastError()}")
            return
        }
        dim = d
        ready = true
        Log.i(TAG, "engine ready, dim=$dim")
        val next = config ?: loadBundledConfig(context) ?: return
        applyConfigOnExecutor(next)
    }

    private fun loadBundledConfig(context: Context): ExemplarConfig? = try {
        val raw = context.assets.open("default_router_exemplars.json")
            .bufferedReader().use { it.readText() }
        json.decodeFromString(ExemplarConfig.serializer(), raw)
    } catch (e: Exception) {
        Log.w(TAG, "bundled exemplar config unreadable: ${e.message}")
        null
    }

    private fun applyConfigOnExecutor(newConfig: ExemplarConfig) {
        config = newConfig
        if (!ready) return  // embedded later, at the end of initOnExecutor
        val m = newConfig.mean?.let { list ->
            if (list.size != dim) {
                Log.w(TAG, "config v${newConfig.version}: mean dim ${list.size} != $dim, ignoring mean")
                null
            } else FloatArray(dim) { list[it].toFloat() }
        }
        val vectors = newConfig.categories.mapValues { (_, texts) ->
            texts.mapNotNull { raw ->
                embedOnExecutor(ExemplarScorer.normalize(raw))?.let { v ->
                    if (m != null) ExemplarScorer.center(v, m) else v
                }
            }
        }
        mean = m
        exemplars = vectors
        Log.i(TAG, "exemplar config v${newConfig.version} applied: " +
            "${vectors.values.sumOf { it.size }} vectors")
    }

    private fun embedOnExecutor(text: String): FloatArray? {
        val out = FloatArray(dim)
        return if (nativeEmbed(text, out) < 0) {
            Log.w(TAG, "embed failed: ${nativeLastError()}")
            null
        } else out
    }
}

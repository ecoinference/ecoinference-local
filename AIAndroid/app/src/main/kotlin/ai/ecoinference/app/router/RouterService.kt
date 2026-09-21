package ai.ecoinference.app.router

import android.content.Context
import ai.ecoinference.app.BuildConfig  // generated from namespace in build.gradle.kts
import ai.ecoinference.app.inference.InferenceMessage
import com.google.firebase.remoteconfig.FirebaseRemoteConfig
import com.google.firebase.remoteconfig.FirebaseRemoteConfigSettings
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.Json

enum class RouterTier { LOCAL, CLOUD }

data class RouterDecision(
    val tier: RouterTier,
    val reason: String,
    val ruleId: String?,
    val facts: Map<String, FactValue>,
)

/**
 * Decides whether a prompt should go to the on-device model or the cloud
 * (Gemini) backend. Pure decision logic — does not perform inference itself.
 * Mirrors iOS RouterService.swift.
 */
class RouterService private constructor(private val context: Context) {

    companion object {
        @Volatile private var instance: RouterService? = null
        private const val REMOTE_CONFIG_KEY = "router_rules"
        private const val EXEMPLARS_CONFIG_KEY = "router_exemplars"

        fun getInstance(context: Context): RouterService =
            instance ?: synchronized(this) {
                instance ?: RouterService(context.applicationContext).also { instance = it }
            }
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val remoteConfig = FirebaseRemoteConfig.getInstance().also { rc ->
        val interval = if (BuildConfig.DEBUG) 0L else 3600L
        val settings = FirebaseRemoteConfigSettings.Builder()
            .setMinimumFetchIntervalInSeconds(interval)
            .build()
        rc.setConfigSettingsAsync(settings)
    }

    @Volatile
    var ruleSet: RouterRuleSet = loadBundledDefault()
        private set

    fun decide(
        prompt: String,
        history: List<InferenceMessage> = emptyList(),
        hasImage: Boolean = false,
        localSupportsImage: Boolean = false,
    ): RouterDecision {
        val facts = RouterFactExtractor.extract(prompt, history, hasImage)
        facts["localSupportsImage"] = FactValue.BoolValue(localSupportsImage)
        // Needle embedding facts replace the keyword-derived semantic facts
        // when the engine is available (docs/ROUTING.md §4). Null on any
        // failure — keyword facts stand (fail open; routing never blocks chat).
        NeedleEmbedder.semanticFacts(prompt)?.let { facts.putAll(it) }

        val outcome = RuleEngine.decide(facts, ruleSet)
        val tier = if (outcome.decision == "cloud") RouterTier.CLOUD else RouterTier.LOCAL
        return RouterDecision(tier, outcome.reason, outcome.ruleId, facts)
    }

    sealed class RefreshResult {
        data class Updated(val newVersion: Int) : RefreshResult()
        data class AlreadyCurrent(val version: Int) : RefreshResult()
        object NoRemoteValue : RefreshResult()
        data class Error(val message: String) : RefreshResult()
    }

    /**
     * Checks Firebase Remote Config for a newer rule set and swaps it in if found.
     * Returns a [RefreshResult] describing what happened — useful for manual test
     * triggers in dev builds. Failures leave the current rule set in place.
     * Mirrors iOS RouterService.refreshFromRemote().
     */
    suspend fun refreshFromRemote(): RefreshResult {
        return try {
            remoteConfig.fetchAndActivate().await()
            refreshExemplars()

            val raw = remoteConfig.getString(REMOTE_CONFIG_KEY)
            if (raw.isEmpty()) return RefreshResult.NoRemoteValue

            val remote = json.decodeFromString(RouterRuleSet.serializer(), raw)
            if (remote.version > ruleSet.version) {
                ruleSet = remote
                RefreshResult.Updated(remote.version)
            } else {
                RefreshResult.AlreadyCurrent(ruleSet.version)
            }
        } catch (e: Exception) {
            RefreshResult.Error(e.message ?: "Unknown error")
        }
    }

    /**
     * Piggybacks the exemplar config (Needle embedder) on the same fetch:
     * version-gated, failures keep the current config. Malformed JSON is
     * logged and ignored — a bad push must not take down rule refresh.
     */
    private fun refreshExemplars() {
        val raw = remoteConfig.getString(EXEMPLARS_CONFIG_KEY)
        if (raw.isEmpty()) return
        try {
            NeedleEmbedder.applyConfigIfNewer(
                json.decodeFromString(NeedleEmbedder.ExemplarConfig.serializer(), raw)
            )
        } catch (e: Exception) {
            android.util.Log.w("RouterService", "invalid $EXEMPLARS_CONFIG_KEY: ${e.message}")
        }
    }

    private fun loadBundledDefault(): RouterRuleSet = try {
        val raw = context.assets.open("default_router_rules.json").bufferedReader().use { it.readText() }
        json.decodeFromString(RouterRuleSet.serializer(), raw)
    } catch (e: Exception) {
        // Never crash on a missing/malformed asset — fail open to "always local".
        RouterRuleSet(version = 0, rules = emptyList(), defaultDecision = "local")
    }
}

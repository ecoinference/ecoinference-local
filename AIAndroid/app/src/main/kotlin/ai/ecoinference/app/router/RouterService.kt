package ai.ecoinference.app.router

import android.content.Context
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

        fun getInstance(context: Context): RouterService =
            instance ?: synchronized(this) {
                instance ?: RouterService(context.applicationContext).also { instance = it }
            }
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val remoteConfig = FirebaseRemoteConfig.getInstance().also { rc ->
        val settings = FirebaseRemoteConfigSettings.Builder()
            .setMinimumFetchIntervalInSeconds(3600)  // 1 hour — mirrors iOS
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

        val outcome = RuleEngine.decide(facts, ruleSet)
        val tier = if (outcome.decision == "cloud") RouterTier.CLOUD else RouterTier.LOCAL
        return RouterDecision(tier, outcome.reason, outcome.ruleId, facts)
    }

    /**
     * Checks Firebase Remote Config for a newer rule set and swaps it in if found.
     * Call once at app launch — failures are silent and leave the current rule set
     * in place, so this is safe to call offline or before anything is published.
     * Mirrors iOS RouterService.refreshFromRemote().
     */
    suspend fun refreshFromRemote() {
        try {
            val activated = remoteConfig.fetchAndActivate().await()
            if (!activated) return

            val raw = remoteConfig.getString(REMOTE_CONFIG_KEY)
            if (raw.isEmpty()) return

            val remote = json.decodeFromString(RouterRuleSet.serializer(), raw)
            if (remote.version > ruleSet.version) {
                ruleSet = remote
            }
        } catch (_: Exception) {
            // Network error or malformed remote JSON — keep the current rule set.
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

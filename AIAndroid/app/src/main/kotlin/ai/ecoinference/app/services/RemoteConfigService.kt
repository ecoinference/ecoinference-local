package ai.ecoinference.app.services

import com.google.firebase.remoteconfig.FirebaseRemoteConfig
import com.google.firebase.remoteconfig.ktx.remoteConfigSettings
import kotlinx.coroutines.tasks.await
import org.json.JSONArray

/**
 * Fetches the server-side model allowlist from Firebase Remote Config.
 *
 * The "available_models" parameter is a JSON array of objects, each with at
 * minimum an "id" field. Only models whose IDs appear in this list are shown
 * in the catalog. Falls back to showing all hardcoded models if the fetch
 * fails (the Firebase Function enforces the allowlist server-side regardless).
 */
object RemoteConfigService {

    private const val KEY = "available_models"
    private const val FETCH_INTERVAL_SEC = 3600L   // 1 hour in production

    private val rc: FirebaseRemoteConfig by lazy {
        FirebaseRemoteConfig.getInstance().also { config ->
            config.setConfigSettingsAsync(
                remoteConfigSettings { minimumFetchIntervalInSeconds = FETCH_INTERVAL_SEC }
            )
        }
    }

    /**
     * Fetches and activates Remote Config, then returns the set of enabled
     * model IDs. Returns null if the fetch fails or the parameter is absent.
     */
    suspend fun fetchEnabledModelIds(): Set<String>? = runCatching {
        rc.fetchAndActivate().await()
        val raw = rc.getString(KEY).takeIf { it.isNotBlank() } ?: return@runCatching null
        val arr = JSONArray(raw)
        buildSet {
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.optString("id")?.takeIf { it.isNotBlank() }?.let { add(it) }
            }
        }.takeIf { it.isNotEmpty() }
    }.getOrNull()
}

package ai.ecoinference.app.services

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences>
    by preferencesDataStore(name = "eco_inference_settings")

/**
 * Persists user preferences via DataStore.
 * Mirrors the role of iOS SettingsService.swift.
 */
class SettingsService private constructor(private val context: Context) {

    companion object {
        @Volatile private var instance: SettingsService? = null

        fun getInstance(context: Context): SettingsService =
            instance ?: synchronized(this) {
                instance ?: SettingsService(context.applicationContext).also { instance = it }
            }

        private val KEY_USE_GPU              = booleanPreferencesKey("use_gpu")
        private val KEY_GEMINI_API_KEY       = stringPreferencesKey("gemini_api_key")
        private val KEY_SYSTEM_PROMPT        = stringPreferencesKey("system_prompt")
        private val KEY_MAX_TOKENS           = intPreferencesKey("max_tokens")
        private val KEY_TEMPERATURE          = floatPreferencesKey("temperature")
        private val KEY_LIFETIME_LOCAL_COUNT = intPreferencesKey("lifetime_local_count")
        private val KEY_LIFETIME_CLOUD_COUNT = intPreferencesKey("lifetime_cloud_count")

        const val DEFAULT_MAX_TOKENS  = 2048
        const val DEFAULT_TEMPERATURE = 0.8f
    }

    // ── GPU backend ───────────────────────────────────────────────────────────

    val useGpuFlow = context.dataStore.data.map { it[KEY_USE_GPU] ?: false }
    suspend fun useGpu(): Boolean = useGpuFlow.first()
    suspend fun setUseGpu(enabled: Boolean) {
        context.dataStore.edit { it[KEY_USE_GPU] = enabled }
    }

    // ── Gemini API key (cloud tier of the LLM router) ───────────────────────────

    val geminiApiKeyFlow = context.dataStore.data.map { it[KEY_GEMINI_API_KEY] ?: "" }
    suspend fun geminiApiKey(): String = geminiApiKeyFlow.first()
    suspend fun setGeminiApiKey(key: String) {
        context.dataStore.edit { it[KEY_GEMINI_API_KEY] = key }
    }

    // ── System prompt ─────────────────────────────────────────────────────────

    val systemPromptFlow = context.dataStore.data.map { it[KEY_SYSTEM_PROMPT] ?: "" }
    suspend fun systemPrompt(): String = systemPromptFlow.first()
    suspend fun setSystemPrompt(prompt: String) {
        context.dataStore.edit { it[KEY_SYSTEM_PROMPT] = prompt }
    }

    // ── Max tokens ────────────────────────────────────────────────────────────

    val maxTokensFlow = context.dataStore.data.map { it[KEY_MAX_TOKENS] ?: DEFAULT_MAX_TOKENS }
    suspend fun maxTokens(): Int = maxTokensFlow.first()
    suspend fun setMaxTokens(tokens: Int) {
        context.dataStore.edit { it[KEY_MAX_TOKENS] = tokens }
    }

    // ── Temperature ───────────────────────────────────────────────────────────

    val temperatureFlow = context.dataStore.data.map { it[KEY_TEMPERATURE] ?: DEFAULT_TEMPERATURE }
    suspend fun temperature(): Float = temperatureFlow.first()
    suspend fun setTemperature(temp: Float) {
        context.dataStore.edit { it[KEY_TEMPERATURE] = temp }
    }

    // ── Lifetime usage counters ───────────────────────────────────────────────

    val lifetimeLocalCountFlow = context.dataStore.data.map { it[KEY_LIFETIME_LOCAL_COUNT] ?: 0 }
    val lifetimeCloudCountFlow = context.dataStore.data.map { it[KEY_LIFETIME_CLOUD_COUNT] ?: 0 }

    suspend fun incrementLifetimeLocal() {
        context.dataStore.edit { it[KEY_LIFETIME_LOCAL_COUNT] = (it[KEY_LIFETIME_LOCAL_COUNT] ?: 0) + 1 }
    }
    suspend fun incrementLifetimeCloud() {
        context.dataStore.edit { it[KEY_LIFETIME_CLOUD_COUNT] = (it[KEY_LIFETIME_CLOUD_COUNT] ?: 0) + 1 }
    }
}

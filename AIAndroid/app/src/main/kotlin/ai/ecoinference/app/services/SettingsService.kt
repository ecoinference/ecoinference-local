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

        private val KEY_USE_GPU       = booleanPreferencesKey("use_gpu")
        private val KEY_HF_TOKEN      = stringPreferencesKey("hf_token")
        private val KEY_SYSTEM_PROMPT = stringPreferencesKey("system_prompt")
        private val KEY_MAX_TOKENS    = intPreferencesKey("max_tokens")
        private val KEY_TEMPERATURE   = floatPreferencesKey("temperature")

        const val DEFAULT_MAX_TOKENS  = 2048
        const val DEFAULT_TEMPERATURE = 0.8f
    }

    // ── GPU backend ───────────────────────────────────────────────────────────

    val useGpuFlow = context.dataStore.data.map { it[KEY_USE_GPU] ?: false }
    suspend fun useGpu(): Boolean = useGpuFlow.first()
    suspend fun setUseGpu(enabled: Boolean) {
        context.dataStore.edit { it[KEY_USE_GPU] = enabled }
    }

    // ── HuggingFace token ─────────────────────────────────────────────────────

    val hfTokenFlow = context.dataStore.data.map { it[KEY_HF_TOKEN] ?: "" }
    suspend fun hfToken(): String = hfTokenFlow.first()
    suspend fun setHfToken(token: String) {
        context.dataStore.edit { it[KEY_HF_TOKEN] = token }
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
}

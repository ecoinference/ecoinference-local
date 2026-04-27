package com.gemma4.aiserver.config

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences>
    by preferencesDataStore(name = "ai_server_settings")

class SettingsRepository(private val context: Context) {

    companion object {
        private val KEY_PORT         = intPreferencesKey("port")
        private val KEY_USE_GPU      = booleanPreferencesKey("use_gpu")
        private val KEY_LOADED_MODEL = stringPreferencesKey("loaded_model_id")

        const val DEFAULT_PORT = 8080
    }

    // ── Port ──────────────────────────────────────────────────────────────────

    val portFlow = context.dataStore.data.map { it[KEY_PORT] ?: DEFAULT_PORT }

    suspend fun port(): Int = portFlow.first()

    suspend fun setPort(port: Int) {
        context.dataStore.edit { it[KEY_PORT] = port }
    }

    // ── GPU backend ───────────────────────────────────────────────────────────

    val useGpuFlow = context.dataStore.data.map { it[KEY_USE_GPU] ?: false }

    suspend fun useGpu(): Boolean = useGpuFlow.first()

    suspend fun setUseGpu(enabled: Boolean) {
        context.dataStore.edit { it[KEY_USE_GPU] = enabled }
    }

    // ── Last loaded model (survives service restart) ──────────────────────────

    val loadedModelIdFlow = context.dataStore.data.map { it[KEY_LOADED_MODEL] }

    suspend fun loadedModelId(): String? = loadedModelIdFlow.first()

    suspend fun setLoadedModelId(id: String?) {
        context.dataStore.edit {
            if (id == null) it.remove(KEY_LOADED_MODEL)
            else it[KEY_LOADED_MODEL] = id
        }
    }
}

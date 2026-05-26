package ai.ecoinference.app

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import ai.ecoinference.app.inference.InferenceService
import ai.ecoinference.app.models.ModelCatalog
import ai.ecoinference.app.models.ModelInfo
import ai.ecoinference.app.services.DownloadService
import ai.ecoinference.app.services.SettingsService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Central application state — mirrors iOS AppState.swift.
 *
 * All UI state is exposed as [StateFlow]s. Methods mirror the iOS counterparts
 * so the Android and iOS code remain easy to keep in sync.
 */
class AppState(private val appContext: Context) : ViewModel() {

    companion object {
        fun factory(context: Context) = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                AppState(context.applicationContext) as T
        }
    }

    private val inference = InferenceService.getInstance(appContext)
    private val download  = DownloadService.getInstance(appContext)
    val settings          = SettingsService.getInstance(appContext)

    // ── Model state ───────────────────────────────────────────────────────────

    private val _modelLoaded        = MutableStateFlow(false)
    val modelLoaded: StateFlow<Boolean> = _modelLoaded.asStateFlow()

    private val _loadedModelId      = MutableStateFlow<String?>(null)
    val loadedModelId: StateFlow<String?> = _loadedModelId.asStateFlow()

    private val _isLoading          = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _loadError          = MutableStateFlow<String?>(null)
    val loadError: StateFlow<String?> = _loadError.asStateFlow()

    private val _loadErrorModelId   = MutableStateFlow<String?>(null)
    val loadErrorModelId: StateFlow<String?> = _loadErrorModelId.asStateFlow()

    /** True when the loaded model supports image attachment in the UI. */
    private val _imageInputEnabled  = MutableStateFlow(false)
    val imageInputEnabled: StateFlow<Boolean> = _imageInputEnabled.asStateFlow()

    // ── Download state ────────────────────────────────────────────────────────

    private val _downloadActive     = MutableStateFlow(false)
    val downloadActive: StateFlow<Boolean> = _downloadActive.asStateFlow()

    private val _downloadProgress   = MutableStateFlow(0f)
    val downloadProgress: StateFlow<Float> = _downloadProgress.asStateFlow()

    private val _downloadingModelId = MutableStateFlow<String?>(null)
    val downloadingModelId: StateFlow<String?> = _downloadingModelId.asStateFlow()

    private val _downloadError      = MutableStateFlow<String?>(null)
    val downloadError: StateFlow<String?> = _downloadError.asStateFlow()

    private val _downloadErrorModelId = MutableStateFlow<String?>(null)
    val downloadErrorModelId: StateFlow<String?> = _downloadErrorModelId.asStateFlow()

    // ── Catalog ───────────────────────────────────────────────────────────────

    private val _models             = MutableStateFlow<List<ModelInfo>>(emptyList())
    val models: StateFlow<List<ModelInfo>> = _models.asStateFlow()

    // ── Deep link ─────────────────────────────────────────────────────────────

    val deepLink = MutableStateFlow<DeepLinkAction?>(null)

    // ── Init ──────────────────────────────────────────────────────────────────

    init {
        refreshCatalog()
    }

    // ── Catalog ───────────────────────────────────────────────────────────────

    fun refreshCatalog() {
        val loadedId = inference.loadedModelId
        _models.value = ModelCatalog.all.map { info ->
            info.copy(
                downloaded = download.isDownloaded(info),
                loaded     = info.id == loadedId,
            )
        }
        _imageInputEnabled.value =
            _models.value.firstOrNull { it.loaded }?.supportsImageInput ?: false
    }

    // ── Download ──────────────────────────────────────────────────────────────

    fun startDownload(modelId: String, hfToken: String? = null) {
        val info = ModelCatalog.findById(modelId) ?: return
        if (_downloadActive.value) return

        _downloadActive.value       = true
        _downloadProgress.value     = 0f
        _downloadingModelId.value   = modelId
        _downloadError.value        = null
        _downloadErrorModelId.value = null

        viewModelScope.launch {
            try {
                val token = hfToken?.takeIf { it.isNotBlank() }
                    ?: settings.hfToken().takeIf { it.isNotBlank() }
                download.download(model = info, hfToken = token) { progress ->
                    _downloadProgress.value = (progress * 100).toFloat()
                }
                _downloadActive.value     = false
                _downloadProgress.value   = 100f
                _downloadingModelId.value = null
                refreshCatalog()
            } catch (e: Exception) {
                _downloadActive.value       = false
                _downloadError.value        = e.message ?: "Download failed"
                _downloadErrorModelId.value = modelId
                _downloadingModelId.value   = null
                refreshCatalog()
            }
        }
    }

    fun cancelDownload() {
        download.cancel()
    }

    fun deleteModel(modelId: String) {
        val info = ModelCatalog.findById(modelId) ?: return
        download.deleteModel(info)
        refreshCatalog()
    }

    // ── Model load / unload ───────────────────────────────────────────────────

    fun loadModel(modelId: String, useGpu: Boolean = false) {
        val info = ModelCatalog.findById(modelId) ?: return
        if (!download.isDownloaded(info)) return

        _isLoading.value        = true
        _loadError.value        = null
        _loadErrorModelId.value = null

        viewModelScope.launch {
            try {
                inference.load(
                    modelId      = modelId,
                    modelPath    = download.filePath(info).absolutePath,
                    useGpu       = useGpu,
                    maxNumTokens = info.maxContextTokens,
                    multimodal   = info.supportsVision,
                )
                _modelLoaded.value      = true
                _loadedModelId.value    = modelId
                _isLoading.value        = false
                _loadError.value        = null
                _loadErrorModelId.value = null
                refreshCatalog()
            } catch (e: Exception) {
                _loadError.value        = e.message ?: "Load failed"
                _loadErrorModelId.value = modelId
                _isLoading.value        = false
                refreshCatalog()
            }
        }
    }

    fun unloadModel() {
        inference.unload()
        _modelLoaded.value      = false
        _loadedModelId.value    = null
        _loadError.value        = null
        _loadErrorModelId.value = null
        _imageInputEnabled.value = false
        refreshCatalog()
    }
}

package com.gemma4.aiserver.download

import android.content.Context
import com.gemma4.aiserver.catalog.ModelCatalog
import com.gemma4.aiserver.model.DownloadProgress
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

class DownloadRepository(private val context: Context) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)   // no timeout — files are multi-GB
        .build()

    private val _progress = MutableStateFlow<DownloadProgress?>(null)

    /** Current download progress. Null when no download is active. */
    val progressFlow: StateFlow<DownloadProgress?> = _progress.asStateFlow()

    val isDownloading: Boolean
        get() = _progress.value?.status == "downloading"

    /** Absolute path where [modelFileName] will be stored. */
    fun modelFilePath(modelFileName: String): String =
        File(context.filesDir, modelFileName).absolutePath

    /** Returns true if the model file exists and is non-empty on disk. */
    fun isDownloaded(modelId: String): Boolean {
        val model = ModelCatalog.findById(modelId) ?: return false
        val file = File(context.filesDir, model.fileName)
        return file.exists() && file.length() > 1024 * 1024
    }

    /**
     * Downloads [modelId] from its catalog URL.
     *
     * Progress is emitted on [progressFlow]. Throws on network error.
     * Cancellation (via coroutine cancellation) cancels the download and
     * emits a "cancelled" progress event.
     */
    suspend fun download(modelId: String) {
        val model = ModelCatalog.findById(modelId)
            ?: throw IllegalArgumentException("Unknown model_id: $modelId")

        if (isDownloading) {
            throw IllegalStateException(
                "Download already in progress for ${_progress.value?.modelId}"
            )
        }

        val destFile = File(context.filesDir, model.fileName)
        val tempFile = File(context.filesDir, "${model.fileName}.tmp")

        _progress.value = DownloadProgress(
            modelId = modelId,
            status = "downloading",
            percent = 0,
        )

        try {
            withContext(Dispatchers.IO) {
                // Gemma 4 models are ungated — no Authorization header needed.
                val request = Request.Builder().url(model.downloadUrl).build()

                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        throw Exception("HTTP ${response.code}: ${response.message}")
                    }

                    val body = response.body
                        ?: throw Exception("Empty response body")
                    val totalBytes = body.contentLength()

                    tempFile.outputStream().buffered().use { out ->
                        var bytesRead = 0L
                        val buffer = ByteArray(64 * 1024)

                        body.byteStream().use { input ->
                            while (true) {
                                // Respect coroutine cancellation
                                if (Thread.currentThread().isInterrupted) {
                                    throw CancellationException("Download cancelled")
                                }
                                val n = input.read(buffer)
                                if (n == -1) break
                                out.write(buffer, 0, n)
                                bytesRead += n

                                val percent = if (totalBytes > 0) {
                                    ((bytesRead.toDouble() / totalBytes) * 100).toInt()
                                } else 0

                                _progress.value = DownloadProgress(
                                    modelId = modelId,
                                    status = "downloading",
                                    percent = percent,
                                    bytesReceived = bytesRead,
                                    totalBytes = totalBytes,
                                )
                            }
                        }
                    }

                    // Atomic rename — only replace the real file when complete
                    tempFile.renameTo(destFile)
                }
            }

            _progress.value = DownloadProgress(
                modelId = modelId,
                status = "complete",
                percent = 100,
            )

        } catch (e: CancellationException) {
            tempFile.delete()
            _progress.value = DownloadProgress(
                modelId = modelId,
                status = "cancelled",
            )
            throw e // re-throw so the coroutine cancels properly
        } catch (e: Exception) {
            tempFile.delete()
            _progress.value = DownloadProgress(
                modelId = modelId,
                status = "error",
                error = e.message ?: "Unknown error",
            )
            throw e
        }
    }

    /**
     * Deletes the model file for [modelId] from disk.
     * No-op if the file does not exist.
     */
    fun deleteModel(modelId: String) {
        val model = ModelCatalog.findById(modelId) ?: return
        File(context.filesDir, model.fileName).delete()
    }

    /** Clears the progress state after a terminal event (complete/error/cancelled). */
    fun clearProgress() {
        _progress.value = null
    }
}

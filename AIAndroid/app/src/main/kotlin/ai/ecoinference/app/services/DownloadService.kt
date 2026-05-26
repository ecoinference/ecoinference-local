package ai.ecoinference.app.services

import android.content.Context
import ai.ecoinference.app.models.ModelCatalog
import ai.ecoinference.app.models.ModelInfo
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Handles model file downloads.
 * Mirrors the role of iOS DownloadService.swift.
 */
class DownloadService private constructor(private val context: Context) {

    companion object {
        @Volatile private var instance: DownloadService? = null

        fun getInstance(context: Context): DownloadService =
            instance ?: synchronized(this) {
                instance ?: DownloadService(context.applicationContext).also { instance = it }
            }
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)   // no timeout — files are multi-GB
        .build()

    /** Absolute path where [model] will be stored. */
    fun filePath(model: ModelInfo): File =
        File(context.filesDir, model.fileName)

    /** Returns true if the model file exists and is non-empty on disk. */
    fun isDownloaded(model: ModelInfo): Boolean {
        val file = filePath(model)
        return file.exists() && file.length() > 1024 * 1024
    }

    /**
     * Downloads [model] from its catalog URL, reporting progress via [onProgress] (0.0–1.0).
     *
     * Pass [hfToken] when the model is gated on HuggingFace. If the download
     * returns HTTP 401/403 and no token was supplied, the error message contains
     * "license_required" so the caller can prompt the user.
     *
     * Supports coroutine cancellation — cancels the download and cleans up the
     * temp file.
     */
    suspend fun download(
        model:      ModelInfo,
        hfToken:    String? = null,
        onProgress: (Double) -> Unit = {},
    ) = withContext(Dispatchers.IO) {
        val destFile = filePath(model)
        val tempFile = File(context.filesDir, "${model.fileName}.tmp")

        try {
            val requestBuilder = Request.Builder().url(model.downloadUrl)
            if (!hfToken.isNullOrBlank()) {
                requestBuilder.addHeader("Authorization", "Bearer $hfToken")
            }

            client.newCall(requestBuilder.build()).execute().use { response ->
                if (response.code == 401 || response.code == 403) {
                    throw Exception(
                        "license_required: HTTP ${response.code} — " +
                        "accept the licence at ${model.licenseUrl ?: model.downloadUrl} " +
                        "then retry with a HuggingFace token."
                    )
                }
                if (!response.isSuccessful) {
                    throw Exception("HTTP ${response.code}: ${response.message}")
                }

                val body       = response.body ?: throw Exception("Empty response body")
                val totalBytes = body.contentLength()

                tempFile.outputStream().buffered().use { out ->
                    var bytesRead = 0L
                    val buffer    = ByteArray(64 * 1024)

                    body.byteStream().use { input ->
                        while (true) {
                            if (Thread.currentThread().isInterrupted) {
                                throw CancellationException("Download cancelled")
                            }
                            val n = input.read(buffer)
                            if (n == -1) break
                            out.write(buffer, 0, n)
                            bytesRead += n

                            val progress = if (totalBytes > 0) {
                                bytesRead.toDouble() / totalBytes.toDouble()
                            } else 0.0
                            onProgress(progress)
                        }
                    }
                }

                // Atomic rename — only replace the real file when complete
                tempFile.renameTo(destFile)
                onProgress(1.0)
            }
        } catch (e: CancellationException) {
            tempFile.delete()
            throw e
        } catch (e: Exception) {
            tempFile.delete()
            throw e
        }
    }

    /** Cancels any in-progress download by interrupting the download thread. */
    fun cancel() {
        client.dispatcher.cancelAll()
    }

    /** Deletes the on-disk file for [model]. No-op if not present. */
    fun deleteModel(model: ModelInfo) {
        filePath(model).delete()
    }
}

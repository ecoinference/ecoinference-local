package ai.ecoinference.app.services

import android.content.Context
import ai.ecoinference.app.models.ModelInfo
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

/** Mirrors iOS's DownloadError.insufficientStorage. */
class InsufficientStorageException(requiredMb: Int, availableMb: Int) :
    Exception("Not enough storage: this model needs ~$requiredMb MB, but only $availableMb MB is free.")

/** Snapshot of an in-progress download, passed to the [DownloadService.download] callback. */
data class DownloadProgress(
    /** 0.0–1.0 */
    val fraction: Double,
    /** Instantaneous speed since the previous callback, in bytes/sec. */
    val bytesPerSecond: Double,
    /** Estimated seconds remaining at the current speed. [Double.POSITIVE_INFINITY] if unknown. */
    val etaSeconds: Double,
)

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
     * Fetches a presigned B2 download URL from Firebase Functions, then streams
     * the model file to disk. Progress is reported via [onProgress].
     * Supports coroutine cancellation — cancels the in-flight request and
     * removes the temp file.
     */
    suspend fun download(
        model:      ModelInfo,
        onProgress: (DownloadProgress) -> Unit = {},
    ) = withContext(Dispatchers.IO) {
        val destFile = filePath(model)
        val tempFile = File(context.filesDir, "${model.fileName}.tmp")

        // 10% buffer for filesystem overhead and the temp file existing
        // alongside the final destination momentarily during the move.
        val requiredBytes = model.fileSizeMb.toLong() * 1_000_000 * 11 / 10
        val availableBytes = destFile.parentFile?.usableSpace ?: Long.MAX_VALUE
        if (availableBytes < requiredBytes) {
            throw InsufficientStorageException(
                requiredMb  = (requiredBytes / 1_000_000).toInt(),
                availableMb = (availableBytes / 1_000_000).toInt(),
            )
        }

        try {
            val presignedUrl = B2Service.modelDownloadUrl(model.id, model.fileName)

            client.newCall(Request.Builder().url(presignedUrl).build()).execute().use { response ->
                if (!response.isSuccessful) {
                    throw Exception("HTTP ${response.code}: ${response.message}")
                }

                val body       = response.body ?: throw Exception("Empty response body")
                val totalBytes = body.contentLength()

                tempFile.outputStream().buffered().use { out ->
                    var bytesRead = 0L
                    val buffer    = ByteArray(64 * 1024)
                    var lastCallbackTime  = System.nanoTime()
                    var lastCallbackBytes = 0L

                    body.byteStream().use { input ->
                        while (true) {
                            if (Thread.currentThread().isInterrupted) {
                                throw CancellationException("Download canceled")
                            }
                            val n = input.read(buffer)
                            if (n == -1) break
                            out.write(buffer, 0, n)
                            bytesRead += n

                            val now             = System.nanoTime()
                            val elapsedSeconds   = (now - lastCallbackTime) / 1_000_000_000.0
                            val bytesPerSecond   = if (elapsedSeconds > 0) {
                                (bytesRead - lastCallbackBytes) / elapsedSeconds
                            } else 0.0
                            lastCallbackTime  = now
                            lastCallbackBytes = bytesRead

                            val fraction = if (totalBytes > 0) {
                                bytesRead.toDouble() / totalBytes.toDouble()
                            } else 0.0
                            val remaining  = totalBytes - bytesRead
                            val etaSeconds = if (bytesPerSecond > 0) remaining / bytesPerSecond else Double.POSITIVE_INFINITY

                            onProgress(DownloadProgress(fraction, bytesPerSecond, etaSeconds))
                        }
                    }
                }

                // Atomic rename — only replace the real file when complete
                tempFile.renameTo(destFile)
                onProgress(DownloadProgress(1.0, 0.0, 0.0))
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

package com.gemma4.aiserver.server.routes

import com.gemma4.aiserver.catalog.ModelCatalog
import com.gemma4.aiserver.config.SettingsRepository
import com.gemma4.aiserver.download.DownloadRepository
import com.gemma4.aiserver.inference.InferenceRepository
import com.gemma4.aiserver.model.DownloadProgress
import com.gemma4.aiserver.model.DownloadRequest
import com.gemma4.aiserver.model.DownloadStartedResponse
import com.gemma4.aiserver.model.ErrorResponse
import com.gemma4.aiserver.model.LoadRequest
import com.gemma4.aiserver.model.LoadResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.response.respondBytesWriter
import io.ktor.server.routing.Route
import io.ktor.server.routing.delete
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.utils.io.writeStringUtf8
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

fun Route.modelRoutes(
    inference: InferenceRepository,
    download: DownloadRepository,
    settings: SettingsRepository,
    serviceScope: CoroutineScope,
) {
    var downloadJob: Job? = null

    // ── Download ──────────────────────────────────────────────────────────────

    /**
     * POST /v1/models/download
     * Triggers download of a model. Returns 202 immediately.
     * Monitor progress via GET /v1/models/download/progress.
     */
    post("/v1/models/download") {
        val req = runCatching { call.receive<DownloadRequest>() }.getOrNull()
            ?: return@post call.respond(
                HttpStatusCode.BadRequest,
                ErrorResponse("Invalid request body"),
            )

        if (!ModelCatalog.isAndroidModel(req.modelId)) {
            return@post call.respond(
                HttpStatusCode.BadRequest,
                ErrorResponse("Unknown model_id: ${req.modelId}"),
            )
        }

        if (download.isDownloading) {
            return@post call.respond(
                HttpStatusCode.Conflict,
                ErrorResponse("Download already in progress"),
            )
        }

        // Launch download in the service scope so it outlives this HTTP call.
        // Pass the optional HF token; it may be null for ungated models.
        downloadJob = serviceScope.launch(Dispatchers.IO) {
            runCatching { download.download(req.modelId, hfToken = req.hfToken) }
            downloadJob = null
        }

        call.respond(
            HttpStatusCode.Accepted,
            DownloadStartedResponse(modelId = req.modelId),
        )
    }

    /**
     * GET /v1/models/download/progress
     * SSE stream of DownloadProgress events.
     * Emits the current state immediately, then streams updates until
     * a terminal status (complete / error / cancelled) is reached.
     */
    get("/v1/models/download/progress") {
        call.respondBytesWriter(contentType = ContentType.Text.EventStream) {
            // Emit current snapshot immediately so the client isn't left waiting.
            val current = download.progressFlow.value
            if (current != null) {
                writeStringUtf8("data: ${Json.encodeToString(current)}\n\n")
                flush()
            }

            if (current == null || current.status != "downloading") {
                writeStringUtf8("data: [DONE]\n\n")
                flush()
                return@respondBytesWriter
            }

            // Stream updates until terminal state.
            download.progressFlow.collect { progress ->
                if (progress == null) return@collect
                writeStringUtf8("data: ${Json.encodeToString(progress)}\n\n")
                flush()
                if (progress.status != "downloading") {
                    writeStringUtf8("data: [DONE]\n\n")
                    flush()
                    return@collect
                }
            }
        }
    }

    /**
     * DELETE /v1/models/download
     * Cancels the active download. 404 if none is in progress.
     */
    delete("/v1/models/download") {
        if (!download.isDownloading) {
            return@delete call.respond(
                HttpStatusCode.NotFound,
                ErrorResponse("No download in progress"),
            )
        }
        downloadJob?.cancel()
        downloadJob = null
        call.respond(mapOf("status" to "cancelled"))
    }

    /**
     * DELETE /v1/models/{model_id}
     * Deletes a downloaded model file from disk.
     * Unloads first if this model is currently loaded.
     */
    delete("/v1/models/{model_id}") {
        val modelId = call.parameters["model_id"]
            ?: return@delete call.respond(
                HttpStatusCode.BadRequest,
                ErrorResponse("Missing model_id"),
            )

        if (inference.loadedModelId == modelId) {
            inference.unload()
            settings.setLoadedModelId(null)
        }

        download.deleteModel(modelId)
        call.respond(mapOf("status" to "deleted", "model_id" to modelId))
    }

    // ── Load / unload ─────────────────────────────────────────────────────────

    /**
     * POST /v1/models/load
     * Loads a downloaded model into the inference engine.
     * Returns 200 when the model is fully loaded and ready.
     * This is a synchronous call — the response arrives only after loading
     * completes so AIClient can rely on 200 = ready.
     */
    post("/v1/models/load") {
        val req = runCatching { call.receive<LoadRequest>() }.getOrNull()
            ?: return@post call.respond(
                HttpStatusCode.BadRequest,
                ErrorResponse("Invalid request body"),
            )

        if (!download.isDownloaded(req.modelId)) {
            return@post call.respond(
                HttpStatusCode.UnprocessableEntity,
                ErrorResponse("Model ${req.modelId} is not downloaded"),
            )
        }

        val model = ModelCatalog.findById(req.modelId)
            ?: return@post call.respond(
                HttpStatusCode.BadRequest,
                ErrorResponse("Unknown model_id: ${req.modelId}"),
            )

        val modelPath = download.modelFilePath(model.fileName)

        runCatching {
            inference.load(
                modelId = req.modelId,
                modelPath = modelPath,
                useGpu = req.useGpu,
                maxTokens = req.maxTokens,
            )
            settings.setLoadedModelId(req.modelId)
        }.fold(
            onSuccess = {
                call.respond(LoadResponse(modelId = req.modelId, status = "loaded"))
            },
            onFailure = { e ->
                call.respond(
                    HttpStatusCode.InternalServerError,
                    LoadResponse(
                        modelId = req.modelId,
                        status = "error",
                        error = e.message,
                    ),
                )
            },
        )
    }

    /**
     * POST /v1/models/unload
     * Unloads the current model and frees inference resources.
     */
    post("/v1/models/unload") {
        val modelId = inference.loadedModelId
        inference.unload()
        settings.setLoadedModelId(null)
        call.respond(
            mapOf(
                "status" to "unloaded",
                "model_id" to (modelId ?: "none"),
            )
        )
    }
}

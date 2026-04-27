package com.gemma4.aiserver.server.routes

import com.gemma4.aiserver.config.SettingsRepository
import com.gemma4.aiserver.download.DownloadRepository
import com.gemma4.aiserver.inference.InferenceRepository
import com.gemma4.aiserver.model.HealthResponse
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get

fun Route.healthRoutes(
    inference: InferenceRepository,
    download: DownloadRepository,
    settings: SettingsRepository,
) {
    get("/health") {
        call.respond(
            HealthResponse(
                modelLoaded = inference.isLoaded,
                modelId = inference.loadedModelId,
                port = settings.port(),
                downloadActive = download.isDownloading,
            )
        )
    }
}

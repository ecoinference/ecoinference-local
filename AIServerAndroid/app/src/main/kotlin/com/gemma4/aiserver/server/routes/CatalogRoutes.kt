package com.gemma4.aiserver.server.routes

import com.gemma4.aiserver.catalog.ModelCatalog
import com.gemma4.aiserver.download.DownloadRepository
import com.gemma4.aiserver.inference.InferenceRepository
import com.gemma4.aiserver.model.CatalogResponse
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get

fun Route.catalogRoutes(
    inference: InferenceRepository,
    download: DownloadRepository,
) {
    /**
     * Returns the Android model catalog with live downloaded/loaded state
     * so AIClient can render the model picker without additional round-trips.
     */
    get("/v1/catalog") {
        val models = ModelCatalog.androidModels.map { model ->
            model.copy(
                downloaded = download.isDownloaded(model.id),
                loaded = inference.loadedModelId == model.id,
            )
        }
        call.respond(CatalogResponse(models = models))
    }
}

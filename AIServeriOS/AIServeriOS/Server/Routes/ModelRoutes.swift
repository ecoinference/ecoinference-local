import Foundation

func registerModelRoutes(router: Router) {

    // POST /v1/models/load
    router.add("POST", "/v1/models/load") { request in
        guard let req = try? request.decode(LoadRequest.self) else {
            return HttpResponse.error("Invalid JSON body", status: 400)
        }

        guard let modelInfo = ModelCatalog.find(id: req.modelId) else {
            return HttpResponse.error("Unknown model_id: \(req.modelId)", status: 404)
        }

        let download = DownloadService.shared
        guard download.isDownloaded(modelInfo) else {
            return HttpResponse.error(
                "Model \(req.modelId) not downloaded. Call /v1/models/download first.",
                status: 409
            )
        }

        let inference = InferenceService.shared
        let modelPath = download.filePath(for: modelInfo).path

        // inference.load() is blocking (5–30 s); run off the cooperative pool
        let result = await Task.detached(priority: .userInitiated) {
            Result { try inference.load(
                modelId:      req.modelId,
                modelPath:    modelPath,
                useGpu:       req.useGpu,
                maxNumTokens: req.maxNumTokens,
                multimodal:   modelInfo.supportsVision
            )}
        }.value
        switch result {
        case .success:
            return HttpResponse.json(LoadResponse(
                modelId: req.modelId,
                status:  "loaded",
                error:   nil
            ))
        case .failure(let error):
            return HttpResponse.json(
                LoadResponse(modelId: req.modelId, status: "error",
                             error: error.localizedDescription),
                status: 500
            )
        }
    }

    // POST /v1/models/unload
    router.add("POST", "/v1/models/unload") { _ in
        InferenceService.shared.unload()
        return HttpResponse.json(UnloadResponse(status: "unloaded"))
    }
}

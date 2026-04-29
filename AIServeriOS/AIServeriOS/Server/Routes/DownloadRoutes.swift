import Foundation

func registerDownloadRoutes(router: Router) {

    // POST /v1/models/download
    // Streams SSE events: { model_id, progress, status, error? }
    router.add("POST", "/v1/models/download") { request in
        guard let req = try? request.decode(DownloadRequest.self) else {
            return HttpResponse.error("Invalid JSON body", status: 400)
        }

        guard let modelInfo = ModelCatalog.find(id: req.modelId) else {
            return HttpResponse.error("Unknown model_id: \(req.modelId)", status: 404)
        }

        let download = DownloadService.shared
        if download.isDownloading {
            return HttpResponse.error("A download is already in progress.", status: 409)
        }

        // Resolve HF token: request body takes priority, else persisted setting
        let token = req.hfToken ?? SettingsService.shared.hfToken

        let stream = AsyncStream<String> { continuation in
            Task.detached(priority: .background) {
                let encoder = JSONEncoder()

                func send(_ evt: DownloadProgressEvent) {
                    let json = (try? encoder.encode(evt))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    continuation.yield(json)
                }

                do {
                    try await download.download(model: modelInfo, hfToken: token) { progress in
                        send(DownloadProgressEvent(
                            modelId:  req.modelId,
                            progress: progress * 100,
                            status:   "downloading"
                        ))
                    }
                    send(DownloadProgressEvent(
                        modelId:  req.modelId,
                        progress: 100,
                        status:   "complete"
                    ))
                } catch {
                    send(DownloadProgressEvent(
                        modelId: req.modelId,
                        status:  "error",
                        error:   error.localizedDescription
                    ))
                }
                continuation.finish()
            }
        }

        return HttpResponse.sse(stream)
    }

    // DELETE /v1/models/download — cancel active download
    router.add("DELETE", "/v1/models/download") { _ in
        DownloadService.shared.cancel()
        return HttpResponse.json(UnloadResponse(status: "cancelled"))
    }
}

import Foundation

func registerHealthRoutes(router: Router, port: UInt16) {
    router.add("GET", "/health") { _ in
        let inference = InferenceService.shared
        let download  = DownloadService.shared
        return HttpResponse.json(HealthResponse(
            status:         "ok",
            modelLoaded:    inference.isLoaded,
            port:           Int(port),
            downloadActive: download.isDownloading,
            version:        "1.0.0"
        ))
    }
}

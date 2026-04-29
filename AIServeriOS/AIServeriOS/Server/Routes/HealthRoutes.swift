import Foundation

func registerHealthRoutes(router: Router) {
    router.add("GET", "/health") { _ in
        let inference = InferenceService.shared
        let download  = DownloadService.shared
        // Read port live so a settings change is reflected without re-registering routes.
        let port      = SettingsService.shared.serverPort
        return HttpResponse.json(HealthResponse(
            status:         "ok",
            modelLoaded:    inference.isLoaded,
            port:           Int(port),
            downloadActive: download.isDownloading,
            version:        "1.0.0"
        ))
    }
}

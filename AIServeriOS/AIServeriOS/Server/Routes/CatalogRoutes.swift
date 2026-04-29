import Foundation

func registerCatalogRoutes(router: Router) {
    router.add("GET", "/v1/catalog") { _ in
        let download  = DownloadService.shared
        let inference = InferenceService.shared
        let loadedId  = inference.loadedModelId

        let models = ModelCatalog.all.map { info -> ModelInfo in
            var m = info
            m.downloaded = download.isDownloaded(m)
            m.loaded     = (m.id == loadedId)
            return m
        }
        return HttpResponse.json(CatalogResponse(models: models))
    }
}

import Foundation

/// A single entry in the model catalog.
struct ModelInfo: Codable, Identifiable {
    let id: String
    let displayName: String
    let fileName: String
    /// Approximate model size in megabytes (for display).
    let fileSizeMb: Int
    /// "ios" | "android" | "all"
    let platform: String
    let requiresHfToken: Bool
    let licenseUrl: String?
    let downloadUrl: String
    var downloaded: Bool
    var loaded: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName    = "display_name"
        case fileName       = "file_name"
        case fileSizeMb     = "file_size_mb"
        case platform
        case requiresHfToken = "requires_hf_token"
        case licenseUrl     = "license_url"
        case downloadUrl    = "download_url"
        case downloaded
        case loaded
    }

    /// Size formatted for display, e.g. "2.5 GB".
    var sizeLabel: String {
        let gb = Double(fileSizeMb) / 1024.0
        return String(format: "%.1f GB", gb)
    }
}

// MARK: - Catalog

enum ModelCatalog {

    // ── iOS models (.litertlm via LiteRT-LM C API) ────────────────────────────

    private static let piBase = "https://models.example.invalid"
    private static let hfBase = "https://huggingface.co"

    static let all: [ModelInfo] = [
        ModelInfo(
            id:              "gemma4-e2b-it",
            displayName:     "Gemma 4 E2B",
            fileName:        "gemma-4-E2B-it.litertlm",
            fileSizeMb:      2580,
            platform:        "ios",
            requiresHfToken: false,
            licenseUrl:      "\(hfBase)/litert-community/gemma-4-E2B-it-litert-lm",
            downloadUrl:     "\(piBase)/gemma-4-E2B-it.litertlm",
            downloaded:      false,
            loaded:          false
        ),
        ModelInfo(
            id:              "gemma4-e4b-it",
            displayName:     "Gemma 4 E4B",
            fileName:        "gemma-4-E4B-it.litertlm",
            fileSizeMb:      3650,
            platform:        "ios",
            requiresHfToken: false,
            licenseUrl:      "\(hfBase)/litert-community/gemma-4-E4B-it-litert-lm",
            downloadUrl:     "\(piBase)/gemma-4-E4B-it.litertlm",
            downloaded:      false,
            loaded:          false
        ),
    ]

    static func find(id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }
}

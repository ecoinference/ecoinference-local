import Foundation
import FirebaseStorage
import UIKit

final class StorageService {
    static let shared = StorageService()

    private let storage = Storage.storage()
    private let maxBytes: Int64 = 4 * 1024 * 1024

    private init() {}

    func uploadAvatar(uid: String, image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw UploadError.encodingFailed
        }
        guard Int64(data.count) <= maxBytes else {
            throw UploadError.imageTooLarge
        }
        let ref = storage.reference().child("avatars/\(uid).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: meta)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    enum UploadError: LocalizedError {
        case encodingFailed, imageTooLarge
        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Could not encode image."
            case .imageTooLarge:  return "Image must be under 4 MB."
            }
        }
    }
}

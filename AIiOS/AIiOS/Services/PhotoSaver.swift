import UIKit
import Photos

/// Saves a UIImage to the user's Photo Library (Camera Roll).
///
/// Usage:
///   await PhotoSaver.save(image)   → returns SaveResult
enum PhotoSaver {

    enum SaveResult {
        case saved
        case denied          // user denied access
        case restricted      // parental controls / MDM
        case failed(Error)
    }

    /// Requests photo-library add permission if needed, then saves `image`.
    static func save(_ image: UIImage) async -> SaveResult {
        let status = await requestAddPermission()
        switch status {
        case .authorized, .limited:
            return await writeToLibrary(image)
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            // requestAddPermission already triggered the prompt; if we land here
            // the user somehow dismissed without deciding — treat as denied.
            return .denied
        @unknown default:
            return .denied
        }
    }

    // MARK: - Private

    private static func requestAddPermission() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    private static func writeToLibrary(_ image: UIImage) async -> SaveResult {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: .saved)
                } else if let error {
                    continuation.resume(returning: .failed(error))
                } else {
                    continuation.resume(returning: .failed(
                        NSError(domain: "PhotoSaver", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Unknown error saving image"])
                    ))
                }
            }
        }
    }
}

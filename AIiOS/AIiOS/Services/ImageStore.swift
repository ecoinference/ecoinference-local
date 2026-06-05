import UIKit

/// Holds the most recently user-attached image so the `edit_image` tool
/// can access it without the model needing to pass base64 in its call.
///
/// ChatView writes to `currentImage` whenever the user picks a photo.
/// ImageEditTools reads `currentImageData` to pass the image to Python.
final class ImageStore {

    static let shared = ImageStore()
    private init() {}

    /// The most recently attached image.  Setting this also updates
    /// `currentImageData` (JPEG, 90% quality).
    var currentImage: UIImage? {
        didSet {
            currentImageData = currentImage?.jpegData(compressionQuality: 0.9)
        }
    }

    /// JPEG-encoded bytes of `currentImage`, ready for base64 encoding.
    private(set) var currentImageData: Data? = nil
}

import Foundation

/// A single turn in a conversation passed to the inference engine.
struct InferenceMessage {
    let role:      String
    let text:      String
    let imageData: Data?

    init(role: String, text: String, imageData: Data? = nil) {
        self.role      = role
        self.text      = text
        self.imageData = imageData
    }
}

import Foundation

struct UserProfile: Codable, Identifiable {
    var id: String          // Firebase UID — stored as both document ID and a field
    var username: String
    var displayName: String
    var bio: String
    var avatarURL: String?
    var phoneNumber: String?
    var createdAt: Date
    var updatedAt: Date
}

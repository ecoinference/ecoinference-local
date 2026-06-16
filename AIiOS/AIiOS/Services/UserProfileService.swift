import Foundation
import FirebaseFirestore

@MainActor
final class UserProfileService: ObservableObject {
    static let shared = UserProfileService()

    @Published private(set) var profile: UserProfile?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    func startListening(uid: String) {
        listener?.remove()
        listener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let snap = snapshot, snap.exists else { return }
                    self?.profile = try? Firestore.Decoder().decode(UserProfile.self, from: snap.data() ?? [:])
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        profile = nil
    }

    func createProfile(uid: String, email: String, username: String, displayName: String) async throws {
        let now = Date()
        let profile = UserProfile(
            id: uid,
            username: username,
            displayName: displayName,
            bio: "",
            avatarURL: nil,
            phoneNumber: nil,
            createdAt: now,
            updatedAt: now
        )
        // Atomic: create user doc + reserve username
        let batch = db.batch()
        let userRef = db.collection("users").document(uid)
        let nameRef = db.collection("usernames").document(username)
        try batch.setData(from: profile, forDocument: userRef)
        batch.setData(["uid": uid], forDocument: nameRef)
        try await batch.commit()
        self.profile = profile
    }

    func updateProfile(uid: String, fields: [String: Any]) async throws {
        var updates = fields
        updates["updatedAt"] = Timestamp(date: Date())
        try await db.collection("users").document(uid).updateData(updates)
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let doc = try await db.collection("usernames").document(username).getDocument()
        return !doc.exists
    }

    func deleteUserData(uid: String, username: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(db.collection("users").document(uid))
        batch.deleteDocument(db.collection("usernames").document(username))
        try await batch.commit()
    }
}

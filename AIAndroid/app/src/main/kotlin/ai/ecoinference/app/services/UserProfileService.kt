package ai.ecoinference.app.services

import ai.ecoinference.app.models.UserProfile
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.tasks.await

object UserProfileService {

    private val db = FirebaseFirestore.getInstance()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _profile = MutableStateFlow<UserProfile?>(null)
    val profile: StateFlow<UserProfile?> = _profile.asStateFlow()

    private var listener: ListenerRegistration? = null

    fun startListening(uid: String) {
        listener?.remove()
        listener = db.collection("users").document(uid)
            .addSnapshotListener { snapshot, _ ->
                if (snapshot != null && snapshot.exists()) {
                    _profile.value = snapshotToProfile(snapshot.data ?: emptyMap())
                }
            }
    }

    fun stopListening() {
        listener?.remove()
        listener = null
        _profile.value = null
    }

    suspend fun createProfile(
        uid: String,
        email: String,
        username: String,
        displayName: String,
    ) {
        val now = Timestamp.now()
        val profile = UserProfile(
            id          = uid,
            username    = username,
            displayName = displayName,
            bio         = "",
            avatarURL   = null,
            phoneNumber = null,
            createdAt   = now,
            updatedAt   = now,
        )
        val batch   = db.batch()
        val userRef = db.collection("users").document(uid)
        val nameRef = db.collection("usernames").document(username)
        batch.set(userRef, profileToMap(profile))
        batch.set(nameRef, mapOf("uid" to uid))
        batch.commit().await()
        _profile.value = profile
    }

    suspend fun updateProfile(uid: String, fields: Map<String, Any?>) {
        val updates = fields.toMutableMap()
        updates["updatedAt"] = Timestamp.now()
        @Suppress("UNCHECKED_CAST")
        db.collection("users").document(uid).update(updates as Map<String, Any>).await()
    }

    suspend fun isUsernameAvailable(username: String): Boolean {
        val doc = db.collection("usernames").document(username).get().await()
        return !doc.exists()
    }

    suspend fun deleteUserData(uid: String, username: String) {
        val batch = db.batch()
        batch.delete(db.collection("users").document(uid))
        batch.delete(db.collection("usernames").document(username))
        batch.commit().await()
    }

    private fun profileToMap(p: UserProfile): Map<String, Any?> = mapOf(
        "id"          to p.id,
        "username"    to p.username,
        "displayName" to p.displayName,
        "bio"         to p.bio,
        "avatarURL"   to p.avatarURL,
        "phoneNumber" to p.phoneNumber,
        "createdAt"   to p.createdAt,
        "updatedAt"   to p.updatedAt,
    )

    private fun snapshotToProfile(data: Map<String, Any?>): UserProfile = UserProfile(
        id          = data["id"] as? String ?: "",
        username    = data["username"] as? String ?: "",
        displayName = data["displayName"] as? String ?: "",
        bio         = data["bio"] as? String ?: "",
        avatarURL   = data["avatarURL"] as? String,
        phoneNumber = data["phoneNumber"] as? String,
        createdAt   = data["createdAt"] as? Timestamp ?: Timestamp.now(),
        updatedAt   = data["updatedAt"] as? Timestamp ?: Timestamp.now(),
    )
}

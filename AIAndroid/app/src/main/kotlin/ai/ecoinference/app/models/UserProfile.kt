package ai.ecoinference.app.models

import com.google.firebase.Timestamp

data class UserProfile(
    val id: String = "",
    val username: String = "",
    val displayName: String = "",
    val bio: String = "",
    val avatarURL: String? = null,
    val phoneNumber: String? = null,
    val createdAt: Timestamp = Timestamp.now(),
    val updatedAt: Timestamp = Timestamp.now(),
)

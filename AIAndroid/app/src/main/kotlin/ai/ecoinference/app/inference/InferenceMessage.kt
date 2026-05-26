package ai.ecoinference.app.inference

/**
 * A single chat turn passed to [LiteRtLmEngine].
 *
 * [imageBytes] carries raw JPEG/PNG bytes for the message's image attachment.
 * Null for text-only turns.
 */
data class InferenceMessage(
    val role: String,
    val text: String,
    val imageBytes: ByteArray? = null,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is InferenceMessage) return false
        return role == other.role && text == other.text &&
                (imageBytes == null) == (other.imageBytes == null)
    }

    override fun hashCode(): Int {
        var result = role.hashCode()
        result = 31 * result + text.hashCode()
        result = 31 * result + (imageBytes?.size ?: 0)
        return result
    }
}

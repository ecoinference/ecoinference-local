package ai.ecoinference.app.services

import android.graphics.Bitmap
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import kotlinx.coroutines.tasks.await
import java.io.ByteArrayOutputStream

object StorageService {

    private val storage = FirebaseStorage.getInstance()
    private const val MAX_BYTES = 4 * 1024 * 1024L

    suspend fun uploadAvatar(uid: String, bitmap: Bitmap): String {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
        val bytes = out.toByteArray()
        if (bytes.size > MAX_BYTES) throw IllegalArgumentException("Image must be under 4 MB.")

        val ref  = storage.reference.child("avatars/$uid.jpg")
        val meta = StorageMetadata.Builder().setContentType("image/jpeg").build()
        ref.putBytes(bytes, meta).await()
        return ref.downloadUrl.await().toString()
    }
}

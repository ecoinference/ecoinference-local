package ai.ecoinference.app.tools

/**
 * Holds the most recently user-attached image bytes for use by `edit_image`.
 * Set from ChatScreen when the user picks or removes a photo.
 *
 * Thread-safe via @Volatile — writes happen on the main thread,
 * reads happen on Dispatchers.Default inside PythonRunner.
 */
object ImageStore {
    @Volatile var currentImageBytes: ByteArray? = null
}

package ai.ecoinference.app

/** Mirrors iOS DeepLinkAction enum. */
sealed class DeepLinkAction {
    data class OpenChat(
        val prefill:      String? = null,
        val autoSend:     Boolean = false,
        val systemPrompt: String? = null,
    ) : DeepLinkAction()

    object OpenModels   : DeepLinkAction()
    object OpenSettings : DeepLinkAction()

    data class LoadModel(val id: String) : DeepLinkAction()

    data class BackgroundInfer(
        val prompt:      String,
        val callbackUrl: String?,
    ) : DeepLinkAction()
}

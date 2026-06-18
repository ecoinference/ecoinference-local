package ai.ecoinference.app.ui.chat

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
// imePadding() intentionally NOT used — adjustResize in the manifest handles
// keyboard avoidance at the window level; adding imePadding() would
// double-count the keyboard height and push the TextField off-screen.
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.ecoinference.app.AppState
import ai.ecoinference.app.inference.InferenceMessage
import ai.ecoinference.app.inference.InferenceService
import ai.ecoinference.app.router.RouterService
import ai.ecoinference.app.router.RouterTier
import ai.ecoinference.app.services.GeminiService
import ai.ecoinference.app.tools.AgentToken
import ai.ecoinference.app.tools.ToolRegistry
import ai.ecoinference.app.tools.runAgentLoop
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.EcoWordmark
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

@Composable
fun ChatScreen(appState: AppState, modifier: Modifier = Modifier) {
    val context           = LocalContext.current
    val modelLoaded       by appState.modelLoaded.collectAsStateWithLifecycle()
    val loadedModelId     by appState.loadedModelId.collectAsStateWithLifecycle()
    val isModelLoading    by appState.isLoading.collectAsStateWithLifecycle()
    val imageInputEnabled by appState.imageInputEnabled.collectAsStateWithLifecycle()

    // Only truly ready when loaded AND the load coroutine has finished
    val modelReady = modelLoaded && !isModelLoading

    var messages          by remember { mutableStateOf(listOf<ChatMessage>()) }
    var inputText         by remember { mutableStateOf("") }
    var pendingImageUri   by remember { mutableStateOf<Uri?>(null) }
    var pendingImageBytes by remember { mutableStateOf<ByteArray?>(null) }
    var isGenerating      by remember { mutableStateOf(false) }
    var generatingJob     by remember { mutableStateOf<Job?>(null) }
    var showClearDialog   by remember { mutableStateOf(false) }

    val listState         = rememberLazyListState()
    val scope             = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    val imagePicker = rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
        pendingImageUri = uri
        if (uri != null) {
            scope.launch {
                val bytes = context.contentResolver.openInputStream(uri)?.readBytes()
                pendingImageBytes = bytes
                ai.ecoinference.app.tools.ImageStore.currentImageBytes = bytes
            }
        } else {
            pendingImageBytes = null
            ai.ecoinference.app.tools.ImageStore.currentImageBytes = null
        }
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    fun sendMessage() {
        val text = inputText.trim()
        if (text.isEmpty() && pendingImageBytes == null) return
        if (!modelReady) {
            val msg = if (isModelLoading) "Model is still loading, please wait…"
                      else "No model loaded — go to Models tab"
            scope.launch { snackbarHostState.showSnackbar(msg) }
            return
        }
        val imageBytes = pendingImageBytes

        // ── Router decision (before mutating messages) ─────────────────────
        val decision = RouterService.getInstance(context).decide(
            prompt             = text,
            history             = messages.map { InferenceMessage(role = it.role, text = it.text) },
            hasImage            = imageBytes != null,
            localSupportsImage  = imageInputEnabled,
        )

        messages = messages + ChatMessage(role = "user", text = text, imageBytes = imageBytes)
        messages = messages + ChatMessage(role = "assistant", text = "", isStreaming = true,
            tier = decision.tier, sourcePrompt = text, routingReason = decision.reason)
        inputText         = ""
        pendingImageUri   = null
        pendingImageBytes = null
        isGenerating      = true

        if (decision.tier == RouterTier.CLOUD) {
            generatingJob = scope.launch {
                try {
                    val apiKey       = appState.settings.geminiApiKey()
                    val systemPrompt = appState.settings.systemPrompt().ifBlank { null }

                    // Prior visible turns, independent of the local engine's context —
                    // cloud turns never touch local KV-cache state.
                    val cloudHistory = messages.dropLast(2).mapNotNull { msg ->
                        when {
                            msg.role == "user"                        -> InferenceMessage("user", msg.text)
                            msg.role == "assistant" && msg.text.isNotBlank() -> InferenceMessage("assistant", msg.text)
                            else                                      -> null
                        }
                    }
                    val cloudMessages = cloudHistory + InferenceMessage(
                        role       = "user",
                        text       = text,
                        imageBytes = imageBytes,
                    )

                    val response = GeminiService.chat(
                        messages     = cloudMessages,
                        systemPrompt = systemPrompt,
                        apiKey       = apiKey,
                    )
                    messages = messages.dropLast(1) +
                        ChatMessage(role = "assistant", text = response, tier = RouterTier.CLOUD,
                            routingReason = decision.reason)
                    appState.settings.incrementLifetimeCloud()
                } catch (e: Exception) {
                    messages = messages.dropLast(1) +
                        ChatMessage(role = "assistant", text = "Error: ${e.message}", tier = RouterTier.CLOUD)
                } finally {
                    isGenerating = false
                }
            }
            return
        }

        generatingJob = scope.launch {
            try {
                val systemPrompt   = appState.settings.systemPrompt()
                val toolBlock      = ToolRegistry.systemPromptBlock()
                val combinedSystem = buildString {
                    if (systemPrompt.isNotBlank()) appendLine(systemPrompt)
                    if (toolBlock.isNotBlank()) appendLine(toolBlock)
                }.trim()

                val inferenceMessages = buildList {
                    if (combinedSystem.isNotBlank())
                        add(InferenceMessage(role = "system", text = combinedSystem))
                    messages.dropLast(1).forEach { msg ->
                        if (msg.role != "assistant" || msg.text.isNotBlank())
                            add(InferenceMessage(role = msg.role, text = msg.text,
                                imageBytes = msg.imageBytes))
                    }
                }

                val maxTokens   = appState.settings.maxTokens()
                val temperature = appState.settings.temperature()
                val inference   = InferenceService.getInstance(context)
                val sb          = StringBuilder()

                // Both paths unified as Flow<AgentToken> ─────────────────────
                // Agent path:  runAgentLoop emits Text (full response) then
                //              ChartImage tokens for any charts.
                // Direct path: each streamed token arrives as AgentToken.Text,
                //              giving live streaming UX without chart support.
                val stream = if (ToolRegistry.all().isNotEmpty())
                    runAgentLoop(inferenceMessages, inference, maxTokens, temperature)
                else
                    inference.chatStream(inferenceMessages, maxTokens, temperature)
                        .map { AgentToken.Text(it) }

                var pendingChart: ByteArray? = null

                stream.collect { token ->
                    when (token) {
                        is AgentToken.Text -> {
                            sb.append(token.chunk)
                            messages = messages.dropLast(1) +
                                ChatMessage(role = "assistant", text = sb.toString(),
                                    isStreaming = true, tier = RouterTier.LOCAL)
                        }
                        is AgentToken.ChartImage -> {
                            // Store first chart; additional charts overwrite (rare edge case)
                            pendingChart = token.bytes
                        }
                        is AgentToken.ToolText -> {
                            // Raw tool output — not shown in the chat bubble.
                            // The test runner uses this token; the UI ignores it.
                        }
                    }
                }

                messages = messages.dropLast(1) +
                    ChatMessage(
                        role          = "assistant",
                        text          = sb.toString(),
                        chartBytes    = pendingChart,
                        isStreaming   = false,
                        tier          = RouterTier.LOCAL,
                        sourcePrompt  = text,
                        routingReason = decision.reason,
                    )
                scope.launch { appState.settings.incrementLifetimeLocal() }
            } catch (e: Exception) {
                messages = messages.dropLast(1) +
                    ChatMessage(role = "assistant", text = "Error: ${e.message}", tier = RouterTier.LOCAL)
            } finally {
                isGenerating = false
            }
        }
    }

    fun retryWithCloud(sourceMsg: ChatMessage) {
        val prompt = sourceMsg.sourcePrompt ?: return
        if (isGenerating) return

        // History up to (but not including) the message being retried
        val msgIndex     = messages.indexOf(sourceMsg)
        val priorHistory = messages.take(msgIndex).mapNotNull { msg ->
            when {
                msg.role == "user"                             -> InferenceMessage("user", msg.text)
                msg.role == "assistant" && msg.text.isNotBlank() -> InferenceMessage("assistant", msg.text)
                else                                           -> null
            }
        }
        val cloudMessages = priorHistory + InferenceMessage(
            role       = "user",
            text       = prompt,
            imageBytes = sourceMsg.imageBytes,   // re-attach image if there was one
        )

        val placeholder = ChatMessage(role = "assistant", text = "", isStreaming = true,
            tier = RouterTier.CLOUD, sourcePrompt = prompt,
            routingReason = "Retried with cloud at your request.")
        messages     = messages + placeholder
        isGenerating = true

        generatingJob = scope.launch {
            try {
                val apiKey       = appState.settings.geminiApiKey()
                val systemPrompt = appState.settings.systemPrompt().ifBlank { null }
                val response     = GeminiService.chat(
                    messages     = cloudMessages,
                    systemPrompt = systemPrompt,
                    apiKey       = apiKey,
                )
                messages = messages.dropLast(1) +
                    ChatMessage(role = "assistant", text = response,
                        tier = RouterTier.CLOUD, sourcePrompt = prompt,
                        routingReason = "Retried with cloud at your request.")
                appState.settings.incrementLifetimeCloud()
            } catch (e: Exception) {
                messages = messages.dropLast(1) +
                    ChatMessage(role = "assistant", text = "Error: ${e.message}",
                        tier = RouterTier.CLOUD, sourcePrompt = prompt)
            } finally {
                isGenerating = false
            }
        }
    }

    // ── Clear chat confirmation dialog ────────────────────────────────────────
    if (showClearDialog) {
        AlertDialog(
            onDismissRequest = { showClearDialog = false },
            title            = { Text("Clear chat?") },
            text             = { Text("This will remove all messages. The loaded model stays in memory.") },
            confirmButton    = {
                TextButton(onClick = {
                    showClearDialog   = false
                    generatingJob?.cancel()
                    isGenerating      = false
                    messages          = emptyList()
                    pendingImageUri   = null
                    pendingImageBytes = null
                    inputText         = ""
                }) { Text("Clear", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton    = {
                TextButton(onClick = { showClearDialog = false }) { Text("Cancel") }
            },
        )
    }

    // No inner Scaffold. adjustResize in the manifest shrinks the window when
    // the keyboard opens — no imePadding() needed (adding it double-counts
    // the keyboard height and pushes the TextField off-screen).
    Column(
        modifier = modifier
            .fillMaxSize(),
    ) {
        // ── Compact header (≈48 dp) ───────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.background)
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            EcoWordmark(fontSize = 18.sp, showDotAi = true)
            Spacer(Modifier.weight(1f))
            // Session cloud request counter — shown when at least one cloud response exists
            val sessionCloudCount = messages.count { it.role == "assistant" && it.tier == RouterTier.CLOUD && it.text.isNotBlank() }
            if (sessionCloudCount > 0) {
                Row(
                    modifier = Modifier
                        .padding(end = 8.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF5E5CE6).copy(alpha = 0.12f))
                        .padding(horizontal = 8.dp, vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(Icons.Default.Cloud, contentDescription = null,
                        tint = Color(0xFF5E5CE6), modifier = Modifier.size(12.dp))
                    Text("$sessionCloudCount", color = Color(0xFF5E5CE6), fontSize = 11.sp)
                }
            }
            // Clear chat button — only visible when there are messages
            if (messages.isNotEmpty() && !isGenerating) {
                IconButton(onClick = { showClearDialog = true }) {
                    Icon(
                        Icons.Default.DeleteSweep,
                        contentDescription = "Clear chat",
                        tint     = EcoColors.Green,
                        modifier = Modifier.size(26.dp),
                    )
                }
            }
            // Model status chip — reflects loading / loaded / no-model states
            Surface(
                shape  = MaterialTheme.shapes.small,
                color  = when {
                    isModelLoading -> MaterialTheme.colorScheme.surface
                    modelLoaded    -> EcoColors.CardDark
                    else           -> MaterialTheme.colorScheme.surface
                },
                border = androidx.compose.foundation.BorderStroke(
                    1.dp, when {
                        isModelLoading -> EcoColors.Green.copy(alpha = 0.3f)
                        modelLoaded    -> EcoColors.Green.copy(alpha = 0.5f)
                        else           -> EcoColors.CardBorder
                    }
                ),
            ) {
                Row(
                    modifier          = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    if (isModelLoading) {
                        CircularProgressIndicator(
                            modifier    = Modifier.size(10.dp),
                            strokeWidth = 1.5.dp,
                            color       = EcoColors.DimGreen,
                        )
                    }
                    Text(
                        text     = when {
                            isModelLoading -> "Loading…"
                            modelLoaded    -> loadedModelId ?: "Loaded"
                            else           -> "No model"
                        },
                        style    = MaterialTheme.typography.labelSmall,
                        color    = when {
                            isModelLoading -> EcoColors.DimGreen
                            modelLoaded    -> EcoColors.DimGreen
                            else           -> EcoColors.NearWhite.copy(alpha = 0.4f)
                        },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        HorizontalDivider(color = EcoColors.CardBorder, thickness = 0.5.dp)

        // ── Message list ──────────────────────────────────────────────────────
        LazyColumn(
            state          = listState,
            modifier       = Modifier.weight(1f),
            contentPadding = PaddingValues(vertical = 8.dp),
        ) {
            items(messages) { msg ->
                MessageBubble(
                    message          = msg,
                    onRetryWithCloud = if (msg.tier == RouterTier.LOCAL
                        && !msg.isStreaming && msg.sourcePrompt != null && !isGenerating)
                        { { retryWithCloud(msg) } } else null,
                )
            }
        }

        // ── Model not ready banner ────────────────────────────────────────────
        if (!modelReady) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color    = if (isModelLoading)
                               EcoColors.CardDark
                           else MaterialTheme.colorScheme.surface,
            ) {
                Row(
                    modifier          = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    if (isModelLoading) {
                        CircularProgressIndicator(
                            modifier    = Modifier.size(14.dp),
                            strokeWidth = 2.dp,
                            color       = EcoColors.Green,
                        )
                        Spacer(Modifier.width(10.dp))
                        Text("Loading model, please wait…",
                            style = MaterialTheme.typography.bodySmall,
                            color = EcoColors.DimGreen)
                    } else {
                        Text("No model loaded — go to the Models tab to load one",
                            style = MaterialTheme.typography.bodySmall,
                            color = EcoColors.NearWhite.copy(alpha = 0.5f))
                    }
                }
            }
        }

        // ── Pending image chip ────────────────────────────────────────────────
        if (pendingImageUri != null) {
            Row(
                modifier          = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("📎 Image attached", color = EcoColors.DimGreen,
                    style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.width(8.dp))
                TextButton(onClick = {
                    pendingImageUri = null
                    pendingImageBytes = null
                    ai.ecoinference.app.tools.ImageStore.currentImageBytes = null
                }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall)
                }
            }
        }

        // ── Input bar ─────────────────────────────────────────────────────────
        HorizontalDivider(color = EcoColors.CardBorder, thickness = 0.5.dp)
        Row(
            modifier          = Modifier
                .fillMaxWidth()
                .padding(start = 8.dp, end = 8.dp, top = 8.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (imageInputEnabled && modelReady) {
                IconButton(onClick = {
                    imagePicker.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly))
                }) {
                    Icon(Icons.Default.AttachFile, contentDescription = "Attach image",
                        tint = EcoColors.Green)
                }
            }

            OutlinedTextField(
                value         = inputText,
                onValueChange = { inputText = it },
                modifier      = Modifier.weight(1f),
                enabled       = modelReady && !isGenerating,
                placeholder   = {
                    Text(when {
                        isModelLoading -> "Waiting for model…"
                        !modelLoaded   -> "Load a model first"
                        else           -> "Message"
                    })
                },
                maxLines      = 5,
                colors        = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor    = EcoColors.Green,
                    unfocusedBorderColor  = EcoColors.CardBorder,
                    disabledBorderColor   = EcoColors.CardBorder.copy(alpha = 0.4f),
                    disabledTextColor     = EcoColors.NearWhite.copy(alpha = 0.3f),
                    disabledPlaceholderColor = EcoColors.NearWhite.copy(alpha = 0.3f),
                ),
            )

            if (isGenerating) {
                IconButton(onClick = {
                    generatingJob?.cancel()
                    isGenerating = false
                    if (messages.lastOrNull()?.isStreaming == true)
                        messages = messages.dropLast(1) + messages.last().copy(isStreaming = false)
                }) {
                    Icon(Icons.Default.Stop, contentDescription = "Stop",
                        tint = MaterialTheme.colorScheme.error)
                }
            } else {
                IconButton(
                    onClick  = ::sendMessage,
                    enabled  = modelReady && (inputText.isNotBlank() || pendingImageBytes != null),
                ) {
                    Icon(Icons.Default.Send, contentDescription = "Send",
                        tint = if (modelReady && (inputText.isNotBlank() || pendingImageBytes != null))
                                   EcoColors.Green
                               else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f))
                }
            }
        }

        // Snackbar
        SnackbarHost(snackbarHostState)
    }
}

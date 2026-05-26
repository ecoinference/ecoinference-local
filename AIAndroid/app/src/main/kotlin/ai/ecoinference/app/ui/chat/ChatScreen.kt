package ai.ecoinference.app.ui.chat

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
// imePadding() intentionally NOT used — adjustResize in the manifest handles
// keyboard avoidance at the window level; adding imePadding() would
// double-count the keyboard height and push the TextField off-screen.
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.ecoinference.app.AppState
import ai.ecoinference.app.inference.InferenceMessage
import ai.ecoinference.app.inference.InferenceService
import ai.ecoinference.app.tools.ToolRegistry
import ai.ecoinference.app.tools.runAgentLoop
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.EcoWordmark
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

@Composable
fun ChatScreen(appState: AppState, modifier: Modifier = Modifier) {
    val context           = LocalContext.current
    val modelLoaded       by appState.modelLoaded.collectAsStateWithLifecycle()
    val loadedModelId     by appState.loadedModelId.collectAsStateWithLifecycle()
    val imageInputEnabled by appState.imageInputEnabled.collectAsStateWithLifecycle()

    var messages          by remember { mutableStateOf(listOf<ChatMessage>()) }
    var inputText         by remember { mutableStateOf("") }
    var pendingImageUri   by remember { mutableStateOf<Uri?>(null) }
    var pendingImageBytes by remember { mutableStateOf<ByteArray?>(null) }
    var isGenerating      by remember { mutableStateOf(false) }
    var generatingJob     by remember { mutableStateOf<Job?>(null) }

    val listState         = rememberLazyListState()
    val scope             = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    val imagePicker = rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
        pendingImageUri = uri
        if (uri != null) {
            scope.launch {
                pendingImageBytes = context.contentResolver.openInputStream(uri)?.readBytes()
            }
        } else {
            pendingImageBytes = null
        }
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    fun sendMessage() {
        val text = inputText.trim()
        if (text.isEmpty() && pendingImageBytes == null) return
        if (!modelLoaded) {
            scope.launch { snackbarHostState.showSnackbar("No model loaded — go to Models tab") }
            return
        }
        val imageBytes = pendingImageBytes
        messages = messages + ChatMessage(role = "user", text = text, imageBytes = imageBytes)
        messages = messages + ChatMessage(role = "assistant", text = "", isStreaming = true)
        inputText         = ""
        pendingImageUri   = null
        pendingImageBytes = null
        isGenerating      = true

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

                val stream = if (ToolRegistry.all().isNotEmpty())
                    runAgentLoop(inferenceMessages, inference, maxTokens, temperature)
                else
                    inference.chatStream(inferenceMessages, maxTokens, temperature)

                stream.collect { token ->
                    sb.append(token)
                    messages = messages.dropLast(1) +
                        ChatMessage(role = "assistant", text = sb.toString(), isStreaming = true)
                }
                messages = messages.dropLast(1) +
                    ChatMessage(role = "assistant", text = sb.toString(), isStreaming = false)
            } catch (e: Exception) {
                messages = messages.dropLast(1) +
                    ChatMessage(role = "assistant", text = "Error: ${e.message}")
            } finally {
                isGenerating = false
            }
        }
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
            // Model status chip — compact, right-aligned
            Surface(
                shape  = MaterialTheme.shapes.small,
                color  = if (modelLoaded) EcoColors.CardDark else MaterialTheme.colorScheme.surface,
                border = androidx.compose.foundation.BorderStroke(
                    1.dp, if (modelLoaded) EcoColors.Green.copy(alpha = 0.5f)
                          else EcoColors.CardBorder),
            ) {
                Text(
                    text     = if (modelLoaded) (loadedModelId ?: "Loaded") else "No model",
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                    style    = MaterialTheme.typography.labelSmall,
                    color    = if (modelLoaded) EcoColors.DimGreen
                               else EcoColors.NearWhite.copy(alpha = 0.4f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        HorizontalDivider(color = EcoColors.CardBorder, thickness = 0.5.dp)

        // ── Message list ──────────────────────────────────────────────────────
        LazyColumn(
            state          = listState,
            modifier       = Modifier.weight(1f),
            contentPadding = PaddingValues(vertical = 8.dp),
        ) {
            items(messages) { msg -> MessageBubble(message = msg) }
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
                TextButton(onClick = { pendingImageUri = null; pendingImageBytes = null }) {
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
            if (imageInputEnabled) {
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
                placeholder   = { Text("Message") },
                maxLines      = 5,
                colors        = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor   = EcoColors.Green,
                    unfocusedBorderColor = EcoColors.CardBorder,
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
                    onClick = ::sendMessage,
                    enabled = inputText.isNotBlank() || pendingImageBytes != null,
                ) {
                    Icon(Icons.Default.Send, contentDescription = "Send",
                        tint = if (inputText.isNotBlank() || pendingImageBytes != null)
                                   EcoColors.Green
                               else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f))
                }
            }
        }

        // Snackbar
        SnackbarHost(snackbarHostState)
    }
}

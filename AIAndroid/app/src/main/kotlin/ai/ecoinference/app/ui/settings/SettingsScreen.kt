package ai.ecoinference.app.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.ecoinference.app.AppState
import ai.ecoinference.app.services.SettingsService
import ai.ecoinference.app.ui.theme.EcoColors
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    appState: AppState,
    modifier: Modifier = Modifier,
    onOpenTests: (() -> Unit)? = null,
) {
    val settings          = appState.settings
    val modelLoaded       by appState.modelLoaded.collectAsStateWithLifecycle()
    val loadedModelId     by appState.loadedModelId.collectAsStateWithLifecycle()
    val scope             = rememberCoroutineScope()

    // Settings state — seed from DataStore flows
    val geminiApiKey      by settings.geminiApiKeyFlow.collectAsState(initial = "")
    val systemPrompt      by settings.systemPromptFlow.collectAsState(initial = "")
    val maxTokens         by settings.maxTokensFlow.collectAsState(initial = SettingsService.DEFAULT_MAX_TOKENS)
    val temperature       by settings.temperatureFlow.collectAsState(initial = SettingsService.DEFAULT_TEMPERATURE)
    val useGpu            by settings.useGpuFlow.collectAsState(initial = false)

    var showGeminiKey     by remember { mutableStateOf(false) }
    var localGeminiKey    by remember(geminiApiKey) { mutableStateOf(geminiApiKey) }
    var localSystemPrompt by remember(systemPrompt) { mutableStateOf(systemPrompt) }

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Spacer(Modifier.height(4.dp))

            // ── Cloud AI (router) ────────────────────────────────────────────
            SectionLabel("Cloud AI")
            OutlinedTextField(
                value         = localGeminiKey,
                onValueChange = { localGeminiKey = it },
                modifier      = Modifier.fillMaxWidth(),
                label         = { Text("Gemini API key") },
                singleLine    = true,
                visualTransformation = if (showGeminiKey) VisualTransformation.None
                                       else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon  = {
                    IconButton(onClick = { showGeminiKey = !showGeminiKey }) {
                        Icon(if (showGeminiKey) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (showGeminiKey) "Hide key" else "Show key")
                    }
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor   = EcoColors.Green,
                    unfocusedBorderColor = EcoColors.CardBorder,
                ),
            )
            Text(
                "Used by the router for requests that need a more capable cloud model. " +
                    "Local on-device inference always works without this key.",
                style = MaterialTheme.typography.bodySmall,
                color = EcoColors.NearWhite.copy(alpha = 0.5f),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(
                    onClick = { scope.launch { settings.setGeminiApiKey(localGeminiKey) } },
                    colors  = ButtonDefaults.buttonColors(containerColor = EcoColors.Green,
                        contentColor = EcoColors.DarkInner),
                ) { Text("Save Key") }
                val uriHandler = LocalUriHandler.current
                TextButton(onClick = { uriHandler.openUri("https://aistudio.google.com/apikey") }) {
                    Text("Get a free key")
                }
            }

            Divider(color = EcoColors.CardBorder)

            // ── System Prompt ─────────────────────────────────────────────────
            SectionLabel("System Prompt")
            OutlinedTextField(
                value         = localSystemPrompt,
                onValueChange = { localSystemPrompt = it },
                modifier      = Modifier.fillMaxWidth().height(120.dp),
                label         = { Text("System prompt (optional)") },
                maxLines      = 6,
                colors        = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor   = EcoColors.Green,
                    unfocusedBorderColor = EcoColors.CardBorder,
                ),
            )
            Button(
                onClick = { scope.launch { settings.setSystemPrompt(localSystemPrompt) } },
                colors  = ButtonDefaults.buttonColors(containerColor = EcoColors.Green,
                    contentColor = EcoColors.DarkInner),
            ) { Text("Save Prompt") }

            Divider(color = EcoColors.CardBorder)

            // ── Max Tokens ────────────────────────────────────────────────────
            SectionLabel("Max Output Tokens: $maxTokens")
            Slider(
                value         = maxTokens.toFloat(),
                onValueChange = { scope.launch { settings.setMaxTokens(it.toInt()) } },
                valueRange    = 256f..4096f,
                steps         = 14,   // (4096-256)/256 - 1 = 14 steps of 256
                colors        = SliderDefaults.colors(thumbColor = EcoColors.Green,
                    activeTrackColor = EcoColors.Green),
            )

            // ── Temperature ───────────────────────────────────────────────────
            SectionLabel("Temperature: ${"%.1f".format(temperature)}")
            Slider(
                value         = temperature,
                onValueChange = { scope.launch { settings.setTemperature(it) } },
                valueRange    = 0f..1f,
                steps         = 9,
                colors        = SliderDefaults.colors(thumbColor = EcoColors.Green,
                    activeTrackColor = EcoColors.Green),
            )

            Divider(color = EcoColors.CardBorder)

            // ── GPU toggle ────────────────────────────────────────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment     = Alignment.CenterVertically,
            ) {
                Column {
                    Text("GPU Acceleration",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface)
                    Text("Takes effect on next model load",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
                }
                Switch(
                    checked         = useGpu,
                    onCheckedChange = { scope.launch { settings.setUseGpu(it) } },
                    colors          = SwitchDefaults.colors(checkedThumbColor = EcoColors.DarkInner,
                        checkedTrackColor = EcoColors.Green),
                )
            }

            Divider(color = EcoColors.CardBorder)

            // ── Unload model ──────────────────────────────────────────────────
            if (modelLoaded) {
                Text("Loaded: ${loadedModelId ?: ""}", color = EcoColors.DimGreen,
                    style = MaterialTheme.typography.bodySmall)
                OutlinedButton(
                    onClick = { appState.unloadModel() },
                    colors  = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error),
                    border  = androidx.compose.foundation.BorderStroke(
                        1.dp, MaterialTheme.colorScheme.error),
                ) { Text("Unload Model") }
            }

            // ── Developer ────────────────────────────────────────────────────
            if (onOpenTests != null) {
                Divider(color = EcoColors.CardBorder)
                SectionLabel("Developer")
                Surface(
                    onClick      = onOpenTests,
                    modifier     = Modifier.fillMaxWidth(),
                    shape        = MaterialTheme.shapes.medium,
                    color        = MaterialTheme.colorScheme.surfaceVariant,
                    tonalElevation = 2.dp,
                ) {
                    ListItem(
                        leadingContent = {
                            Icon(
                                Icons.Default.Science,
                                contentDescription = null,
                                tint = EcoColors.Green,
                            )
                        },
                        headlineContent = {
                            Text("Inference Tests",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurface)
                        },
                        supportingContent = {
                            Text(
                                "Smoke tests — inference, Python, cloud, router.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                            )
                        },
                        trailingContent = {
                            Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        },
                        colors = ListItemDefaults.colors(
                            containerColor = androidx.compose.ui.graphics.Color.Transparent,
                        ),
                    )
                }
            }

            // ── Footer ────────────────────────────────────────────────────────
            Spacer(Modifier.height(8.dp))
            Text("EcoInference v1.0.0",
                style = MaterialTheme.typography.bodySmall,
                color = EcoColors.NearWhite.copy(alpha = 0.35f),
                modifier = Modifier.align(Alignment.CenterHorizontally))
            Spacer(Modifier.height(16.dp))
        }
    }

}

@Composable
private fun SectionLabel(text: String) {
    Text(text, style = MaterialTheme.typography.labelLarge, color = EcoColors.DimGreen)
}

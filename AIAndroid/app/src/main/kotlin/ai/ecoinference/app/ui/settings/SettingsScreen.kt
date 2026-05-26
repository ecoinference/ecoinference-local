package ai.ecoinference.app.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
fun SettingsScreen(appState: AppState, modifier: Modifier = Modifier) {
    val settings          = appState.settings
    val modelLoaded       by appState.modelLoaded.collectAsStateWithLifecycle()
    val loadedModelId     by appState.loadedModelId.collectAsStateWithLifecycle()
    val scope             = rememberCoroutineScope()

    // Settings state — seed from DataStore flows
    val hfToken           by settings.hfTokenFlow.collectAsState(initial = "")
    val systemPrompt      by settings.systemPromptFlow.collectAsState(initial = "")
    val maxTokens         by settings.maxTokensFlow.collectAsState(initial = SettingsService.DEFAULT_MAX_TOKENS)
    val temperature       by settings.temperatureFlow.collectAsState(initial = SettingsService.DEFAULT_TEMPERATURE)
    val useGpu            by settings.useGpuFlow.collectAsState(initial = false)

    var showToken         by remember { mutableStateOf(false) }
    var localHfToken      by remember(hfToken) { mutableStateOf(hfToken) }
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

            // ── HuggingFace Token ─────────────────────────────────────────────
            SectionLabel("HuggingFace Token")
            OutlinedTextField(
                value         = localHfToken,
                onValueChange = { localHfToken = it },
                modifier      = Modifier.fillMaxWidth(),
                label         = { Text("HF Token (for gated models)") },
                singleLine    = true,
                visualTransformation = if (showToken) VisualTransformation.None
                                       else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon  = {
                    IconButton(onClick = { showToken = !showToken }) {
                        Icon(if (showToken) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (showToken) "Hide token" else "Show token")
                    }
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor   = EcoColors.Green,
                    unfocusedBorderColor = EcoColors.CardBorder,
                ),
            )
            Button(
                onClick = { scope.launch { settings.setHfToken(localHfToken) } },
                colors  = ButtonDefaults.buttonColors(containerColor = EcoColors.Green,
                    contentColor = EcoColors.DarkInner),
            ) { Text("Save Token") }

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
                    Text("GPU Acceleration", color = EcoColors.NearWhite,
                        style = MaterialTheme.typography.bodyLarge)
                    Text("Takes effect on next model load",
                        style = MaterialTheme.typography.bodySmall,
                        color = EcoColors.NearWhite.copy(alpha = 0.5f))
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

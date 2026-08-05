package ai.ecoinference.app.ui.help

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.ecoinference.app.AppState
import ai.ecoinference.app.DeepLinkAction
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.ecoBrand
import ai.ecoinference.app.ui.theme.ecoAccent

/**
 * Explains EcoInference's model-interaction features — the ones users
 * wouldn't discover just by looking at the UI. Deliberately scoped to how
 * you talk to and get results from the model (tool-calling, `use tool`,
 * images, local/cloud routing) — not Settings/Models/About, which are
 * self-explanatory UI, not hidden capabilities. Mirrors iOS's HelpView.swift.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpScreen(appState: AppState, modifier: Modifier = Modifier) {

    fun tryExample(text: String) {
        appState.deepLink.value = DeepLinkAction.OpenChat(prefill = text)
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Help") },
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
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            Spacer(Modifier.height(4.dp))

            // ── How EcoInference answers ─────────────────────────────────────
            HelpSection("How I Answer") {
                HelpRow(Icons.Default.Memory, "Local by default",
                    "Most questions are answered entirely on your device — private, offline, no data leaves your phone.")
                HelpRow(Icons.Default.Cloud, "Cloud when it helps",
                    "Some requests (current events, very long topics, images the local model can't handle) automatically route to a cloud model instead. Tap the Local/Cloud badge under any reply to see why it was routed there.")
                HelpRow(Icons.AutoMirrored.Filled.ArrowForward, "Try with Cloud",
                    "Not happy with a local answer? Tap \"Try with Cloud\" under it to get a second opinion from the cloud model, using the same conversation so far.")
                HelpRowCloudSetup(Icons.Default.Key, "Setting up Cloud AI")
            }

            // ── Built-in abilities ────────────────────────────────────────────
            HelpSection("Built-in Abilities") {
                Text(
                    "Just ask normally — no special phrasing needed. The model decides on its own when one of these would help:",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    modifier = Modifier.padding(bottom = 4.dp),
                )
                AbilityRow("📍", "Location & device", "your GPS location, battery level, flashlight, an SOS blink, opening a map, pre-filling a text message")
                AbilityRow("🌙", "Sky & time", "moon phase, sunrise/sunset, twilight times for any location")
                AbilityRow("🔢", "Math & data", "statistics, curve fitting, distances/bearings, and other calculations")
                AbilityRow("📊", "Charts", "line, bar, and scatter plots drawn from your data")
                AbilityRow("🖼️", "Photo editing", "crop, rotate, filters, brightness/contrast, and more on an attached image")
                AbilityRow("📱", "QR codes", "generate one from any text, link, or Wi-Fi info")
                Text(
                    "Examples: “where am I”, “what's my battery level”, “plot my sales by month”, “make this photo black and white”.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                    modifier = Modifier.padding(top = 2.dp),
                )
            }

            // ── use tool ───────────────────────────────────────────────────────
            HelpSection("Advanced: “use tool”") {
                Text(
                    "For anything beyond the built-in list above, type “use tool” followed by what you want. The model writes real Python code and runs it on your device right then — not a preview, an actual result.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                )
                Text(
                    "Type “list tools” to see every available library.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                    modifier = Modifier.padding(top = 2.dp, bottom = 8.dp),
                )
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ExampleCard("use tool plot a sine wave") { tryExample(it) }
                    ExampleCard("use tool what moon phase is it tonight") { tryExample(it) }
                    ExampleCard("use tool calculate the standard deviation of 12, 45, 23, 67, 34, 89") { tryExample(it) }
                }
            }

            // ── Images ─────────────────────────────────────────────────────────
            HelpSection("Images") {
                HelpRow(Icons.Default.PhotoLibrary, "Attach a photo",
                    "Tap the paperclip to attach a photo from your camera or library, then ask a question about it — or ask the model to edit it.")
                Text(
                    "On this device, image understanding works with both the Gemma 4 E2B and E4B models.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                )
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun HelpSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface,
            fontWeight = FontWeight.SemiBold)
        content()
    }
}

@Composable
private fun HelpRow(icon: ImageVector, title: String, body: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, contentDescription = null, tint = ecoBrand,
            modifier = Modifier.size(22.dp).padding(top = 2.dp))
        Column {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface)
            Text(body, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
        }
    }
}

/** Same as [HelpRow], but with a real tappable link to the API key page. */
@OptIn(ExperimentalTextApi::class)
@Composable
private fun HelpRowCloudSetup(icon: ImageVector, title: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, contentDescription = null, tint = ecoBrand,
            modifier = Modifier.size(22.dp).padding(top = 2.dp))
        Column {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface)
            val annotated = buildAnnotatedString {
                append("Cloud answers need your own free Gemini API key. Get one at ")
                withLink(
                    LinkAnnotation.Url(
                        "https://aistudio.google.com/apikey",
                        TextLinkStyles(style = SpanStyle(
                            color = ecoAccent,
                            fontWeight = FontWeight.SemiBold,
                            textDecoration = TextDecoration.Underline,
                        )),
                    )
                ) {
                    append("aistudio.google.com/apikey")
                }
                append(", then paste it into Settings → Cloud AI. Local answers always work without one.")
            }
            Text(annotated, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
        }
    }
}

@Composable
private fun AbilityRow(emoji: String, title: String, body: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(emoji, style = MaterialTheme.typography.bodyMedium)
        Column {
            Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
            Text(body, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f))
        }
    }
}

@Composable
private fun ExampleCard(text: String, onTry: (String) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp))
            .clickable { onTry(text) }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
        )
        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = "Try it",
            tint = ecoBrand, modifier = Modifier.size(18.dp))
    }
}

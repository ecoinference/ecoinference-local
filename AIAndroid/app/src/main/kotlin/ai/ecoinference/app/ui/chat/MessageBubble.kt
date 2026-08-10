package ai.ecoinference.app.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import ai.ecoinference.app.router.RouterTier
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.ecoBrand
import ai.ecoinference.app.ui.theme.ecoAccent

/**
 * A single chat message.
 *
 * [imageBytes]  — INPUT image attached by the user (e.g. photo for vision).
 * [chartBytes]  — OUTPUT PNG rendered by a chart tool; displayed inline below text.
 * [tier]        — which tier (local/cloud) produced this response. Assistant only.
 */
@Suppress("ArrayInDataClass")
data class ChatMessage(
    val role:         String,          // "user" | "assistant" | "code" | "tool"
    val text:         String,
    val imageBytes:   ByteArray? = null,   // user-attached input image
    val chartBytes:   ByteArray? = null,   // tool-generated output chart (PNG)
    val isStreaming:   Boolean = false,
    val tier:          RouterTier? = null,
    val sourcePrompt:  String? = null,      // user prompt that produced this response (assistant only)
    val sourceImageBytes: ByteArray? = null, // user-attached image that produced this response (assistant only)
    val routingReason: String? = null,      // why the router chose this tier (assistant only)
)

@Composable
fun MessageBubble(message: ChatMessage, onRetryWithCloud: (() -> Unit)? = null) {
    val isUser      = message.role == "user"
    val isCode      = message.role == "code"
    val isTool      = message.role == "tool"
    val hasChart    = message.chartBytes != null
    val isAssistant = !isUser
    val showRetry   = isAssistant
        && message.tier == RouterTier.LOCAL
        && !message.isStreaming
        && message.text.isNotBlank()
        && message.sourcePrompt != null
        && onRetryWithCloud != null

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Column {
        message.tier?.let { TierBadge(it, reason = message.routingReason) }
        Column(
            modifier = Modifier
                .then(
                    // Chart messages expand to near full width for readability;
                    // regular messages stay capped at 300 dp.
                    if (isAssistant && hasChart)
                        Modifier.fillMaxWidth(0.95f)
                    else
                        Modifier.widthIn(max = 300.dp)
                )
                .clip(
                    RoundedCornerShape(
                        topStart    = if (isUser) 18.dp else 4.dp,
                        topEnd      = if (isUser) 4.dp  else 18.dp,
                        bottomStart = 18.dp,
                        bottomEnd   = 18.dp,
                    )
                )
                .background(if (isUser) EcoColors.Green else MaterialTheme.colorScheme.surface)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalAlignment = if (isUser) Alignment.End else Alignment.Start,
        ) {
            // ── Input image thumbnail (user-attached) ──────────────────────
            message.imageBytes?.let { bytes ->
                AsyncImage(
                    model              = bytes,
                    contentDescription = "Attached image",
                    contentScale       = ContentScale.Crop,
                    modifier           = Modifier
                        .fillMaxWidth()
                        .height(180.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .padding(bottom = 6.dp),
                )
            }

            // ── Tool label (run_python output from `use tool`) ─────────────
            if (isTool) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.padding(bottom = 2.dp),
                ) {
                    Icon(
                        Icons.Default.Build,
                        contentDescription = null,
                        tint     = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(12.dp),
                    )
                    Text(
                        "run_python",
                        fontSize   = 11.sp,
                        fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                        color      = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // ── Text ───────────────────────────────────────────────────────
            if (message.text.isNotEmpty()) {
                if (isCode && !message.isStreaming) {
                    // Generated Python is collapsed by default. It's how the answer
                    // was reached, not the answer — and a full snippet dwarfs the
                    // result underneath it. Still one tap away for anyone who wants
                    // to check the working.
                    var expanded by remember(message.text) { mutableStateOf(false) }
                    Row(
                        modifier = Modifier
                            .clickable { expanded = !expanded }
                            .padding(vertical = 2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(
                            if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                            contentDescription = null,
                            tint     = ecoAccent,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            if (expanded) "Hide Python" else "Show Python",
                            style = MaterialTheme.typography.labelMedium,
                            color = ecoAccent,
                        )
                    }
                    if (expanded) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text       = message.text,
                            color      = MaterialTheme.colorScheme.onSurface,
                            fontSize   = 13.sp,
                            lineHeight = 19.sp,
                            fontFamily = FontFamily.Monospace,
                        )
                    }
                } else {
                    Text(
                        text       = message.text,
                        color      = if (isUser) EcoColors.DarkInner
                                     else if (isTool) MaterialTheme.colorScheme.onSurfaceVariant
                                     else MaterialTheme.colorScheme.onSurface,
                        fontSize   = if (isTool) 12.sp else 15.sp,
                        lineHeight = if (isTool) 17.sp else 22.sp,
                        fontFamily = if (isCode) FontFamily.Monospace else FontFamily.Default,
                    )
                }
            }

            // ── Streaming indicator ────────────────────────────────────────
            if (message.isStreaming && message.text.isEmpty()) {
                CircularProgressIndicator(
                    modifier    = Modifier.size(18.dp),
                    color       = ecoAccent,
                    strokeWidth = 2.dp,
                )
            }

            // ── Output chart (tool-generated PNG) ─────────────────────────
            message.chartBytes?.let { bytes ->
                Spacer(Modifier.height(10.dp))
                AsyncImage(
                    model              = bytes,
                    contentDescription = "Chart",
                    contentScale       = ContentScale.FillWidth,
                    modifier           = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp)),
                )
            }
        }

        // ── Retry with cloud button ────────────────────────────────────────
        if (showRetry) {
            TextButton(
                onClick  = { onRetryWithCloud!!() },
                modifier = Modifier.padding(start = 4.dp, top = 2.dp),
            ) {
                Icon(
                    Icons.Default.Cloud,
                    contentDescription = null,
                    tint     = Color(0xFF5E5CE6),
                    modifier = Modifier.size(14.dp),
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    "Try with Cloud",
                    color    = Color(0xFF5E5CE6),
                    fontSize = 12.sp,
                )
            }
        }
        }
    }
}

@Composable
private fun TierBadge(tier: RouterTier, reason: String? = null) {
    val (label, icon, color) = when (tier) {
        // #5E5CE6 — Apple's systemIndigo (dark variant), matching iOS's Color.indigo
        // as it resolves in this app's dark theme. Keep in sync with ChatView.swift.
        RouterTier.CLOUD -> Triple("Cloud", Icons.Default.Cloud, Color(0xFF5E5CE6))
        RouterTier.LOCAL -> Triple("Local", Icons.Default.Memory, ecoBrand)
    }
    var showReason by remember { mutableStateOf(false) }

    Column {
        Row(
            modifier = Modifier
                .clip(CircleShape)
                .background(color.copy(alpha = 0.12f))
                .then(if (reason != null) Modifier.clickable { showReason = !showReason } else Modifier)
                .padding(horizontal = 6.dp, vertical = 2.dp)
                .padding(bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Icon(icon, contentDescription = label, tint = color, modifier = Modifier.size(11.dp))
            Text(label, color = color, fontSize = 10.sp)
        }
        AnimatedVisibility(visible = showReason && reason != null) {
            Text(
                text     = reason ?: "",
                fontSize = 10.sp,
                color    = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .padding(top = 3.dp)
                    .widthIn(max = 260.dp),
            )
        }
    }
}

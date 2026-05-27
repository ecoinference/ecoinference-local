package ai.ecoinference.app.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import ai.ecoinference.app.ui.theme.EcoColors

/**
 * A single chat message.
 *
 * [imageBytes]  — INPUT image attached by the user (e.g. photo for vision).
 * [chartBytes]  — OUTPUT PNG rendered by a chart tool; displayed inline below text.
 */
@Suppress("ArrayInDataClass")
data class ChatMessage(
    val role:        String,          // "user" | "assistant"
    val text:        String,
    val imageBytes:  ByteArray? = null,   // user-attached input image
    val chartBytes:  ByteArray? = null,   // tool-generated output chart (PNG)
    val isStreaming: Boolean = false,
)

@Composable
fun MessageBubble(message: ChatMessage) {
    val isUser     = message.role == "user"
    val hasChart   = message.chartBytes != null
    val isAssistant = !isUser

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
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
                .background(if (isUser) EcoColors.Green else EcoColors.CardDark)
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

            // ── Text ───────────────────────────────────────────────────────
            if (message.text.isNotEmpty()) {
                Text(
                    text       = message.text,
                    color      = if (isUser) EcoColors.DarkInner else EcoColors.NearWhite,
                    fontSize   = 15.sp,
                    lineHeight = 22.sp,
                )
            }

            // ── Streaming indicator ────────────────────────────────────────
            if (message.isStreaming && message.text.isEmpty()) {
                CircularProgressIndicator(
                    modifier    = Modifier.size(18.dp),
                    color       = EcoColors.DimGreen,
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
    }
}

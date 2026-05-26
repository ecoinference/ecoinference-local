package ai.ecoinference.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment

// ── EcoInference brand colours — mirrors eco_theme.dart EcoColors ─────────────

object EcoColors {
    val Green       = Color(0xFF22C55E)   // main brand green
    val DimGreen    = Color(0xFF4ADE80)   // lighter accent
    val Teal        = Color(0xFF14B8A6)   // teal / .ai suffix
    val DarkInner   = Color(0xFF0A160E)   // radial centre / scaffold bg
    val DarkOuter   = Color(0xFF040806)   // radial edge
    val LightInner  = Color(0xFFDCFCE7)
    val LightOuter  = Color(0xFFBBF7D0)
    val NearWhite   = Color(0xFFF0FDF4)
    val DarkText    = Color(0xFF0F321E)
    val CardDark    = Color(0xFF0F2415)
    val CardBorder  = Color(0xFF1A3A22)
}

private val DarkColors = darkColorScheme(
    primary          = EcoColors.Green,
    onPrimary        = EcoColors.DarkInner,
    primaryContainer = Color(0xFF0F2415),
    secondary        = EcoColors.Teal,
    background       = EcoColors.DarkInner,
    surface          = EcoColors.CardDark,
    surfaceVariant   = Color(0xFF0F2415),
    onBackground     = EcoColors.NearWhite,
    onSurface        = EcoColors.NearWhite,
    onSurfaceVariant = EcoColors.DimGreen,
    outline          = EcoColors.CardBorder,
)

private val LightColors = lightColorScheme(
    primary    = EcoColors.Green,
    onPrimary  = Color.White,
    secondary  = EcoColors.Teal,
    background = EcoColors.LightOuter,
    surface    = EcoColors.LightInner,
    onBackground = EcoColors.DarkText,
    onSurface  = EcoColors.DarkText,
)

@Composable
fun EcoInferenceTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content     = content,
    )
}

// ── EcoWordmark — "EcoInference.ai" with brand colours ───────────────────────

@Composable
fun EcoWordmark(fontSize: TextUnit = 24.sp, showDotAi: Boolean = true) {
    val isDark = isSystemInDarkTheme()
    val inferenceColor = if (isDark) EcoColors.NearWhite else EcoColors.DarkText

    Text(
        text = buildAnnotatedString {
            withStyle(SpanStyle(color = EcoColors.Green, fontWeight = FontWeight.ExtraBold)) {
                append("Eco")
            }
            withStyle(SpanStyle(color = inferenceColor, fontWeight = FontWeight.Light)) {
                append("Inference")
            }
            if (showDotAi) {
                withStyle(SpanStyle(color = EcoColors.Teal, fontWeight = FontWeight.Normal,
                    fontSize = fontSize * 0.58)) {
                    append(".ai")
                }
            }
        },
        fontSize = fontSize,
        letterSpacing = (-0.5).sp,
    )
}

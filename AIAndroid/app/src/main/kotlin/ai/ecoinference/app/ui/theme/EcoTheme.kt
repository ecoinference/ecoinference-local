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
    val DimGreen    = Color(0xFF4ADE80)   // lighter accent — DARK THEME ONLY (see DeepGreen)
    // Light-theme counterpart to DimGreen. DimGreen is a pale accent picked to sit on the
    // dark scheme's near-black surfaces; on the light scheme's pale-green surfaces it drops
    // to roughly 1.5:1 contrast and is effectively unreadable. This is the same hue family
    // but dark enough to pass WCAG AA on both light surfaces (~6.4:1 on LightInner, ~5.9:1
    // on LightOuter), so accent text stays green rather than falling back to plain body text.
    val DeepGreen   = Color(0xFF166534)
    val Teal        = Color(0xFF14B8A6)   // teal / .ai suffix
    val DarkInner   = Color(0xFF0A160E)   // radial centre / scaffold bg
    val DarkOuter   = Color(0xFF040806)   // radial edge
    val LightInner  = Color(0xFFDCFCE7)
    val LightOuter  = Color(0xFFBBF7D0)
    val NearWhite   = Color(0xFFF0FDF4)
    val DarkText    = Color(0xFF0F321E)
    val CardDark    = Color(0xFF0F2415)   // card surface — DARK THEME ONLY
    val CardBorder  = Color(0xFF1A3A22)   // card border  — DARK THEME ONLY
    // Light-theme counterpart to CardBorder. Prefer MaterialTheme.colorScheme.outline
    // over either constant so the right one is picked automatically.
    val LightBorder = Color(0xFF86EFAC)
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

// Mirrors DarkColors slot-for-slot. The surface/background pair keeps the same
// relationship in both themes — cards (surface) sit lighter than the page
// (background) — so components can just use colorScheme.surface and get
// EcoColors.CardDark in dark and EcoColors.LightInner in light automatically.
private val LightColors = lightColorScheme(
    primary          = EcoColors.Green,
    onPrimary        = Color.White,
    secondary        = EcoColors.Teal,
    background       = EcoColors.LightOuter,
    surface          = EcoColors.LightInner,
    surfaceVariant   = EcoColors.LightInner,
    onBackground     = EcoColors.DarkText,
    onSurface        = EcoColors.DarkText,
    onSurfaceVariant = EcoColors.DeepGreen,
    outline          = EcoColors.LightBorder,
)

/**
 * Brand-green accent for text and icons sitting on a **theme-coloured** surface
 * (`colorScheme.surface`/`background`, a ListItem, a bare Row, a TextField…).
 *
 * Use this instead of [EcoColors.DimGreen] in those places. DimGreen is a pale
 * accent picked for the dark scheme's near-black surfaces; on the light scheme's
 * pale-green surfaces it falls to roughly 1.5:1 contrast and reads as washed out.
 *
 * Do NOT use this for content on a hardcoded dark surface — anything inside a
 * `EcoColors.CardDark` card or an `EcoColors.Green` button stays dark in both
 * themes, so plain [EcoColors.DimGreen] is already correct there and swapping it
 * would make dark-on-dark text.
 */
val ecoAccent: Color
    @Composable get() = if (isSystemInDarkTheme()) EcoColors.DimGreen else EcoColors.DeepGreen

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

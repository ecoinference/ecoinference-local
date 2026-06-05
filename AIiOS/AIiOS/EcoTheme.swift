import SwiftUI
import UIKit

// MARK: - EcoColors
//
// Single source of truth for EcoInference brand colors.
// Mirrors AIAndroid/EcoTheme.kt EcoColors object exactly.

enum EcoColors {
    /// Primary brand green — buttons, user bubbles, active indicators. #22C55E
    static let green      = Color(hex: 0x22C55E)
    /// Lighter green — progress indicators, secondary accents. #4ADE80
    static let dimGreen   = Color(hex: 0x4ADE80)
    /// Teal — ".ai" wordmark suffix, secondary accent. #14B8A6
    static let teal       = Color(hex: 0x14B8A6)

    // Dark theme foundation
    /// Deep dark background / icon background. #0A160E
    static let darkInner  = Color(hex: 0x0A160E)
    /// Dark card surface. #0F2415
    static let cardDark   = Color(hex: 0x0F2415)
    /// Card border / divider. #1A3A22
    static let cardBorder = Color(hex: 0x1A3A22)

    // Text
    /// Near-white text on dark surfaces. #F0FDF4
    static let nearWhite  = Color(hex: 0xF0FDF4)
    /// Dark text on light surfaces. #0F321E
    static let darkText   = Color(hex: 0x0F321E)

    // Light theme backgrounds
    /// Light mode page background. #BBF7D0
    static let lightOuter = Color(hex: 0xBBF7D0)
    /// Light mode card surface. #DCCFE7
    static let lightInner = Color(hex: 0xDCCFE7)

    // ── Adaptive (light ↔ dark) ───────────────────────────────────────────────

    /// Main page background: #BBF7D0 in light mode, #0A160E in dark mode.
    /// Drop-in replacement for Color(.systemBackground) throughout the app.
    static let background = Color(uiColor: backgroundUI)

    /// UIKit version of `background` for window/UIView usage in AIiOSApp.
    static let backgroundUI = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x0A/255, green: 0x16/255, blue: 0x0E/255, alpha: 1)
            : UIColor(red: 0xBB/255, green: 0xF7/255, blue: 0xD0/255, alpha: 1)
    }
}

// MARK: - Color(hex:) convenience

private extension Color {
    /// Initialise from a 0xRRGGBB integer literal.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - EcoWordmark

/// Replicates the Android EcoWordmark composable:
///   "Eco" (ExtraBold, green) + "Inference" (Light, primary) + ".ai" (Normal, teal)
/// with −0.5 pt letter-spacing.
struct EcoWordmark: View {
    var fontSize: CGFloat = 24

    var body: some View {
        (
            Text("Eco")
                .fontWeight(.heavy)
                .foregroundStyle(EcoColors.green)
            + Text("Inference")
                .fontWeight(.light)
                .foregroundStyle(Color.primary)
            + Text(".ai")
                .foregroundStyle(EcoColors.teal)
                .font(.system(size: fontSize * 0.58))
        )
        .font(.system(size: fontSize))
        .kerning(-0.5)
    }
}

import 'package:flutter/material.dart';

// ── EcoInference brand colours ────────────────────────────────────────────────

class EcoColors {
  EcoColors._();

  // Primary greens
  static const green    = Color(0xFF22C55E);  // #22C55E — main brand green
  static const dimGreen = Color(0xFF4ADE80);  // #4ADE80 — lighter accent
  static const teal     = Color(0xFF14B8A6);  // #14B8A6 — teal accent / .ai

  // Dark backgrounds
  static const darkInner = Color(0xFF0A160E); // #0A160E — radial centre
  static const darkOuter = Color(0xFF040806); // #040806 — radial edge

  // Light backgrounds
  static const lightInner = Color(0xFFDCFCE7); // #DCFCE7
  static const lightOuter = Color(0xFFBBF7D0); // #BBF7D0

  // Text
  static const nearWhite = Color(0xFFF0FDF4); // #F0FDF4
  static const darkText  = Color(0xFF0F321E); // #0F321E

  // Semantic (mapped to Flutter theme roles)
  static const seed = green; // drives Material3 colour scheme
}

// ── EcoInference ThemeData ────────────────────────────────────────────────────

class EcoTheme {
  EcoTheme._();

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: EcoColors.seed,
        scaffoldBackgroundColor: EcoColors.darkInner,
        appBarTheme: const AppBarTheme(
          backgroundColor: EcoColors.darkInner,
          foregroundColor: EcoColors.nearWhite,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF0F2415),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF1A3A22), width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: EcoColors.green, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: EcoColors.green,
            foregroundColor: EcoColors.darkInner,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: EcoColors.green,
            side: const BorderSide(color: EcoColors.green),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: EcoColors.green,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF0F2415),
          contentTextStyle: const TextStyle(color: EcoColors.nearWhite),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: EcoColors.green, width: 1),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF0F2415),
          side: const BorderSide(color: Color(0xFF1A3A22)),
          labelStyle: const TextStyle(color: EcoColors.dimGreen),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: EcoColors.seed,
        appBarTheme: const AppBarTheme(
          backgroundColor: EcoColors.lightOuter,
          foregroundColor: EcoColors.darkText,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: EcoColors.green,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: EcoColors.green,
            side: const BorderSide(color: EcoColors.green),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: EcoColors.green,
        ),
        snackBarTheme: SnackBarThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
}

// ── EcoInference wordmark widget ──────────────────────────────────────────────

/// Renders "Eco[bold-green]Inference[regular].ai[teal-small]"
/// Drop this anywhere an inline wordmark is needed.
class EcoWordmark extends StatelessWidget {
  const EcoWordmark({super.key, this.fontSize = 24, this.showDotAi = true});

  final double fontSize;
  final bool showDotAi;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inferenceColor = isDark ? EcoColors.nearWhite : EcoColors.darkText;
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.clip,
      text: TextSpan(
        style: TextStyle(fontSize: fontSize, letterSpacing: -0.5),
        children: [
          TextSpan(
            text: 'Eco',
            style: TextStyle(
              color: EcoColors.green,
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
            ),
          ),
          TextSpan(
            text: 'Inference',
            style: TextStyle(
              color: inferenceColor,
              fontWeight: FontWeight.w300,
              fontSize: fontSize,
            ),
          ),
          if (showDotAi)
            TextSpan(
              text: '.ai',
              style: TextStyle(
                color: EcoColors.teal,
                fontWeight: FontWeight.w400,
                fontSize: fontSize * 0.58,
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Daylight Glass design tokens for Crease.
/// Light theme is the primary outdoor-sunlight scheme; dark theme is a
/// first-class scheme for night matches under lights.
class CreaseColors {
  CreaseColors._();

  // Light palette (sampled from approved Comp B)
  static const Color groundLight = Color(0xFFEEF3F3);
  static const Color sageWashTop = Color(0xFFE3F0EA);
  static const Color surfaceGlassLight = Color(0xCCFFFFFF); // 80% white
  static const Color surfaceSheetLight = Color(0xE8F6F8F8); // 91% frosted sheet
  static const Color surfaceKeyLight = Color(0xF2FFFFFF);
  static const Color inkPrimaryLight = Color(0xFF0A0C0C);
  static const Color inkSecondaryLight = Color(0xFF5B6560);
  static const Color hairlineLight = Color(0xFFD5DFDD);
  static const Color hairlineSubtleLight = Color(0xFFE3EAE8);
  static const Color pillMutedBgLight = Color(0xFFE4EAE9);

  // Dark palette (first-class night-match scheme)
  static const Color groundDark = Color(0xFF0E1413);
  static const Color sageWashTopDark = Color(0xFF13221C);
  static const Color surfaceGlassDark = Color(0xCC182220);
  static const Color surfaceSheetDark = Color(0xEB151D1B);
  static const Color surfaceKeyDark = Color(0xFF1E2926);
  static const Color inkPrimaryDark = Color(0xFFF2F6F5);
  static const Color inkSecondaryDark = Color(0xFF9AA8A2);
  static const Color hairlineDark = Color(0xFF2B3834);
  static const Color hairlineSubtleDark = Color(0xFF222E2B);
  static const Color pillMutedBgDark = Color(0xFF202B28);

  // Semantic accents (strictly reserved)
  static const Color pitchGreen = Color(0xFF098558);
  static const Color pitchGreenSoftLight = Color(0xFFDDF1E8);
  static const Color pitchGreenSoftDark = Color(0xFF143528);
  static const Color wicketRed = Color(0xFFD74956);
  static const Color wicketRedSoftLight = Color(0xFFFBE5E7);
  static const Color wicketRedSoftDark = Color(0xFF3A1A1E);
}

class CreaseThemeExtension extends ThemeExtension<CreaseThemeExtension> {
  const CreaseThemeExtension({
    required this.ground,
    required this.sageWashTop,
    required this.surfaceGlass,
    required this.surfaceSheet,
    required this.surfaceKey,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.hairline,
    required this.hairlineSubtle,
    required this.pillMutedBg,
    required this.pitchGreen,
    required this.pitchGreenSoft,
    required this.wicketRed,
    required this.wicketRedSoft,
  });

  final Color ground;
  final Color sageWashTop;
  final Color surfaceGlass;
  final Color surfaceSheet;
  final Color surfaceKey;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color hairline;
  final Color hairlineSubtle;
  final Color pillMutedBg;
  final Color pitchGreen;
  final Color pitchGreenSoft;
  final Color wicketRed;
  final Color wicketRedSoft;

  static const CreaseThemeExtension light = CreaseThemeExtension(
    ground: CreaseColors.groundLight,
    sageWashTop: CreaseColors.sageWashTop,
    surfaceGlass: CreaseColors.surfaceGlassLight,
    surfaceSheet: CreaseColors.surfaceSheetLight,
    surfaceKey: CreaseColors.surfaceKeyLight,
    inkPrimary: CreaseColors.inkPrimaryLight,
    inkSecondary: CreaseColors.inkSecondaryLight,
    hairline: CreaseColors.hairlineLight,
    hairlineSubtle: CreaseColors.hairlineSubtleLight,
    pillMutedBg: CreaseColors.pillMutedBgLight,
    pitchGreen: CreaseColors.pitchGreen,
    pitchGreenSoft: CreaseColors.pitchGreenSoftLight,
    wicketRed: CreaseColors.wicketRed,
    wicketRedSoft: CreaseColors.wicketRedSoftLight,
  );

  static const CreaseThemeExtension dark = CreaseThemeExtension(
    ground: CreaseColors.groundDark,
    sageWashTop: CreaseColors.sageWashTopDark,
    surfaceGlass: CreaseColors.surfaceGlassDark,
    surfaceSheet: CreaseColors.surfaceSheetDark,
    surfaceKey: CreaseColors.surfaceKeyDark,
    inkPrimary: CreaseColors.inkPrimaryDark,
    inkSecondary: CreaseColors.inkSecondaryDark,
    hairline: CreaseColors.hairlineDark,
    hairlineSubtle: CreaseColors.hairlineSubtleDark,
    pillMutedBg: CreaseColors.pillMutedBgDark,
    pitchGreen: CreaseColors.pitchGreen,
    pitchGreenSoft: CreaseColors.pitchGreenSoftDark,
    wicketRed: CreaseColors.wicketRed,
    wicketRedSoft: CreaseColors.wicketRedSoftDark,
  );

  @override
  CreaseThemeExtension copyWith({
    Color? ground,
    Color? sageWashTop,
    Color? surfaceGlass,
    Color? surfaceSheet,
    Color? surfaceKey,
    Color? inkPrimary,
    Color? inkSecondary,
    Color? hairline,
    Color? hairlineSubtle,
    Color? pillMutedBg,
    Color? pitchGreen,
    Color? pitchGreenSoft,
    Color? wicketRed,
    Color? wicketRedSoft,
  }) {
    return CreaseThemeExtension(
      ground: ground ?? this.ground,
      sageWashTop: sageWashTop ?? this.sageWashTop,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      surfaceSheet: surfaceSheet ?? this.surfaceSheet,
      surfaceKey: surfaceKey ?? this.surfaceKey,
      inkPrimary: inkPrimary ?? this.inkPrimary,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      hairline: hairline ?? this.hairline,
      hairlineSubtle: hairlineSubtle ?? this.hairlineSubtle,
      pillMutedBg: pillMutedBg ?? this.pillMutedBg,
      pitchGreen: pitchGreen ?? this.pitchGreen,
      pitchGreenSoft: pitchGreenSoft ?? this.pitchGreenSoft,
      wicketRed: wicketRed ?? this.wicketRed,
      wicketRedSoft: wicketRedSoft ?? this.wicketRedSoft,
    );
  }

  @override
  CreaseThemeExtension lerp(ThemeExtension<CreaseThemeExtension>? other, double t) {
    if (other is! CreaseThemeExtension) return this;
    return CreaseThemeExtension(
      ground: Color.lerp(ground, other.ground, t)!,
      sageWashTop: Color.lerp(sageWashTop, other.sageWashTop, t)!,
      surfaceGlass: Color.lerp(surfaceGlass, other.surfaceGlass, t)!,
      surfaceSheet: Color.lerp(surfaceSheet, other.surfaceSheet, t)!,
      surfaceKey: Color.lerp(surfaceKey, other.surfaceKey, t)!,
      inkPrimary: Color.lerp(inkPrimary, other.inkPrimary, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineSubtle: Color.lerp(hairlineSubtle, other.hairlineSubtle, t)!,
      pillMutedBg: Color.lerp(pillMutedBg, other.pillMutedBg, t)!,
      pitchGreen: Color.lerp(pitchGreen, other.pitchGreen, t)!,
      pitchGreenSoft: Color.lerp(pitchGreenSoft, other.pitchGreenSoft, t)!,
      wicketRed: Color.lerp(wicketRed, other.wicketRed, t)!,
      wicketRedSoft: Color.lerp(wicketRedSoft, other.wicketRedSoft, t)!,
    );
  }
}

extension CreaseThemeContext on BuildContext {
  CreaseThemeExtension get crease =>
      Theme.of(this).extension<CreaseThemeExtension>() ??
      CreaseThemeExtension.light;
}

class CreaseTheme {
  CreaseTheme._();

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    final base = GoogleFonts.interTextTheme().apply(
      bodyColor: primary,
      displayColor: primary,
    );
    return base.copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 64,
        fontWeight: FontWeight.w300,
        letterSpacing: -2.2,
        height: 1.0,
        color: primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: primary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: secondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: primary,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: secondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: CreaseColors.pitchGreen,
      onPrimary: Colors.white,
      secondary: CreaseColors.pitchGreen,
      onSecondary: Colors.white,
      error: CreaseColors.wicketRed,
      onError: Colors.white,
      surface: CreaseColors.groundLight,
      onSurface: CreaseColors.inkPrimaryLight,
      outline: CreaseColors.hairlineLight,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: CreaseColors.groundLight,
      textTheme: _buildTextTheme(
        CreaseColors.inkPrimaryLight,
        CreaseColors.inkSecondaryLight,
      ),
      extensions: const [CreaseThemeExtension.light],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: CreaseColors.inkPrimaryLight,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: CreaseColors.hairlineSubtleLight,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CreaseColors.inkPrimaryLight,
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: CreaseColors.pitchGreen,
      onPrimary: Colors.white,
      secondary: CreaseColors.pitchGreen,
      onSecondary: Colors.white,
      error: CreaseColors.wicketRed,
      onError: Colors.white,
      surface: CreaseColors.groundDark,
      onSurface: CreaseColors.inkPrimaryDark,
      outline: CreaseColors.hairlineDark,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: CreaseColors.groundDark,
      textTheme: _buildTextTheme(
        CreaseColors.inkPrimaryDark,
        CreaseColors.inkSecondaryDark,
      ),
      extensions: const [CreaseThemeExtension.dark],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: CreaseColors.inkPrimaryDark,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: CreaseColors.hairlineSubtleDark,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CreaseColors.surfaceKeyDark,
        contentTextStyle: GoogleFonts.inter(
          color: CreaseColors.inkPrimaryDark,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}


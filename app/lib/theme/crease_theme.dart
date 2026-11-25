import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Strict corner-radius scale locked across Crease so surfaces feel coherent.
class CreaseRadius {
  CreaseRadius._();

  static const double badge = 8;
  static const double control = 12;
  static const double card = 16;
  static const double sheet = 24;
  static const double pill = 999;
}

/// Architectural outdoor-legible palette for Crease.
/// Light mode uses crisp cool-stone canvas + pure white surfaces for bright
/// daylight contrast; dark mode uses true obsidian surfaces for night matches.
class CreaseColors {
  CreaseColors._();

  // Light palette (high-contrast daylight scheme)
  static const Color groundLight = Color(0xFFF4F6F7);
  static const Color sageWashTop = Color(0xFFF4F6F7);
  static const Color surfaceGlassLight = Color(0xFFFFFFFF);
  static const Color surfaceSheetLight = Color(0xFFFFFFFF);
  static const Color surfaceKeyLight = Color(0xFFF6F8F9);
  static const Color inkPrimaryLight = Color(0xFF101315);
  static const Color inkSecondaryLight = Color(0xFF5D666E);
  static const Color hairlineLight = Color(0xFFE2E6E9);
  static const Color hairlineSubtleLight = Color(0xFFECEFF2);
  static const Color pillMutedBgLight = Color(0xFFEBEEF0);

  // Dark palette (crisp night-match obsidian scheme)
  static const Color groundDark = Color(0xFF0D0F11);
  static const Color sageWashTopDark = Color(0xFF0D0F11);
  static const Color surfaceGlassDark = Color(0xFF15191C);
  static const Color surfaceSheetDark = Color(0xFF15191C);
  static const Color surfaceKeyDark = Color(0xFF1E2327);
  static const Color inkPrimaryDark = Color(0xFFF4F6F8);
  static const Color inkSecondaryDark = Color(0xFF8E98A1);
  static const Color hairlineDark = Color(0xFF262C31);
  static const Color hairlineSubtleDark = Color(0xFF1E2328);
  static const Color pillMutedBgDark = Color(0xFF20252A);

  // Semantic accents (strictly reserved)
  static const Color pitchGreen = Color(0xFF0B7A4B);
  static const Color pitchGreenDark = Color(0xFF19A96B);
  static const Color onPitchGreenLight = Color(0xFFFFFFFF);
  static const Color onPitchGreenDark = Color(0xFF07120D);
  static const Color pitchGreenSoftLight = Color(0xFFE6F4ED);
  static const Color pitchGreenSoftDark = Color(0xFF132D22);

  static const Color wicketRed = Color(0xFFD63949);
  static const Color wicketRedDark = Color(0xFFEC5463);
  static const Color onWicketRedLight = Color(0xFFFFFFFF);
  static const Color onWicketRedDark = Color(0xFF1A0709);
  static const Color wicketRedSoftLight = Color(0xFFFCEAEB);
  static const Color wicketRedSoftDark = Color(0xFF34181C);

  // Secondary chart ink (harmonized steel slate for multi-innings comparison)
  static const Color chartSecondaryLight = Color(0xFF3A5A78);
  static const Color chartSecondaryDark = Color(0xFF6B9AC4);
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
    required this.onPitchGreen,
    required this.pitchGreenSoft,
    required this.wicketRed,
    required this.onWicketRed,
    required this.wicketRedSoft,
    required this.chartSecondary,
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
  final Color onPitchGreen;
  final Color pitchGreenSoft;
  final Color wicketRed;
  final Color onWicketRed;
  final Color wicketRedSoft;
  final Color chartSecondary;

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
    onPitchGreen: CreaseColors.onPitchGreenLight,
    pitchGreenSoft: CreaseColors.pitchGreenSoftLight,
    wicketRed: CreaseColors.wicketRed,
    onWicketRed: CreaseColors.onWicketRedLight,
    wicketRedSoft: CreaseColors.wicketRedSoftLight,
    chartSecondary: CreaseColors.chartSecondaryLight,
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
    pitchGreen: CreaseColors.pitchGreenDark,
    onPitchGreen: CreaseColors.onPitchGreenDark,
    pitchGreenSoft: CreaseColors.pitchGreenSoftDark,
    wicketRed: CreaseColors.wicketRedDark,
    onWicketRed: CreaseColors.onWicketRedDark,
    wicketRedSoft: CreaseColors.wicketRedSoftDark,
    chartSecondary: CreaseColors.chartSecondaryDark,
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
    Color? onPitchGreen,
    Color? pitchGreenSoft,
    Color? wicketRed,
    Color? onWicketRed,
    Color? wicketRedSoft,
    Color? chartSecondary,
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
      onPitchGreen: onPitchGreen ?? this.onPitchGreen,
      pitchGreenSoft: pitchGreenSoft ?? this.pitchGreenSoft,
      wicketRed: wicketRed ?? this.wicketRed,
      onWicketRed: onWicketRed ?? this.onWicketRed,
      wicketRedSoft: wicketRedSoft ?? this.wicketRedSoft,
      chartSecondary: chartSecondary ?? this.chartSecondary,
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
      onPitchGreen: Color.lerp(onPitchGreen, other.onPitchGreen, t)!,
      pitchGreenSoft: Color.lerp(pitchGreenSoft, other.pitchGreenSoft, t)!,
      wicketRed: Color.lerp(wicketRed, other.wicketRed, t)!,
      onWicketRed: Color.lerp(onWicketRed, other.onWicketRed, t)!,
      wicketRedSoft: Color.lerp(wicketRedSoft, other.wicketRedSoft, t)!,
      chartSecondary: Color.lerp(chartSecondary, other.chartSecondary, t)!,
    );
  }
}

extension CreaseThemeContext on BuildContext {
  CreaseThemeExtension get crease =>
      Theme.of(this).extension<CreaseThemeExtension>() ??
      CreaseThemeExtension.light;
}

/// Shared athletic numeric style using Barlow + tabular figures for scores,
/// keypad digits, overs, and match figures.
TextStyle creaseNumeralStyle({
  required double fontSize,
  FontWeight fontWeight = FontWeight.w700,
  Color? color,
  double? letterSpacing,
  double? height,
}) {
  return GoogleFonts.barlow(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class CreaseTheme {
  CreaseTheme._();

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    final base = GoogleFonts.plusJakartaSansTextTheme().apply(
      bodyColor: primary,
      displayColor: primary,
    );
    return base.copyWith(
      displayLarge: GoogleFonts.barlow(
        fontSize: 64,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.8,
        height: 0.96,
        color: primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      displayMedium: GoogleFonts.barlow(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.04,
        color: primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.18,
        color: primary,
      ),
      headlineSmall: GoogleFonts.barlow(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: primary,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleSmall: GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      bodyLarge: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: secondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      bodySmall: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: secondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: primary,
      ),
      labelMedium: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: secondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  static InputDecorationTheme _inputTheme(CreaseThemeExtension ext) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(CreaseRadius.control),
      borderSide: BorderSide(color: ext.hairline, width: 1),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: ext.surfaceKey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CreaseRadius.control),
        borderSide: BorderSide(color: ext.pitchGreen, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CreaseRadius.control),
        borderSide: BorderSide(color: ext.wicketRed, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CreaseRadius.control),
        borderSide: BorderSide(color: ext.wicketRed, width: 1.5),
      ),
      labelStyle: GoogleFonts.plusJakartaSans(
        color: ext.inkSecondary,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: GoogleFonts.plusJakartaSans(
        color: ext.inkSecondary.withValues(alpha: 0.72),
        fontSize: 14,
      ),
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme scheme,
    required CreaseThemeExtension ext,
  }) {
    final isDark = brightness == Brightness.dark;
    final textTheme = _buildTextTheme(ext.inkPrimary, ext.inkSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: ext.ground,
      textTheme: textTheme,
      extensions: [ext],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        foregroundColor: ext.inkPrimary,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      inputDecorationTheme: _inputTheme(ext),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ext.pitchGreen,
          foregroundColor: ext.onPitchGreen,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CreaseRadius.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ext.inkPrimary,
          side: BorderSide(color: ext.hairline, width: 1),
          backgroundColor: ext.surfaceGlass,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CreaseRadius.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ext.pitchGreen,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CreaseRadius.badge),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ext.surfaceKey,
        selectedColor: ext.pitchGreen,
        disabledColor: ext.pillMutedBg,
        side: BorderSide(color: ext.hairline, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CreaseRadius.badge + 2),
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: ext.inkPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        showCheckmark: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ext.surfaceSheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: ext.hairline, width: 1),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: ext.surfaceSheet,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CreaseRadius.control + 2),
          side: BorderSide(color: ext.hairline, width: 1),
        ),
        textStyle: textTheme.bodyLarge,
      ),
      dividerTheme: DividerThemeData(
        color: ext.hairlineSubtle,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: isDark ? ext.inkPrimary : CreaseColors.inkPrimaryLight,
        actionTextColor:
            isDark ? CreaseColors.pitchGreen : CreaseColors.pitchGreenDark,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: isDark ? CreaseColors.groundDark : Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CreaseRadius.control),
        ),
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
    return _buildTheme(
      brightness: Brightness.light,
      scheme: scheme,
      ext: CreaseThemeExtension.light,
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: CreaseColors.pitchGreenDark,
      onPrimary: CreaseColors.onPitchGreenDark,
      secondary: CreaseColors.pitchGreenDark,
      onSecondary: CreaseColors.onPitchGreenDark,
      error: CreaseColors.wicketRedDark,
      onError: CreaseColors.onWicketRedDark,
      surface: CreaseColors.groundDark,
      onSurface: CreaseColors.inkPrimaryDark,
      outline: CreaseColors.hairlineDark,
    );
    return _buildTheme(
      brightness: Brightness.dark,
      scheme: scheme,
      ext: CreaseThemeExtension.dark,
    );
  }
}

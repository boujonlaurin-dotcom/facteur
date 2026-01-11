import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Extension de thème pour les couleurs sémantiques personnalisées de Facteur
@immutable
class FacteurColors extends ThemeExtension<FacteurColors> {
  // Backgrounds
  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color surface;
  final Color surfaceElevated;
  final Color surfacePaper;

  // Accents
  final Color primary;
  final Color primaryMuted;
  final Color secondary;

  // Sémantiques
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  // Texte
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textStamp;

  const FacteurColors({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surface,
    required this.surfaceElevated,
    required this.surfacePaper,
    required this.primary,
    required this.primaryMuted,
    required this.secondary,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textStamp,
  });

  @override
  FacteurColors copyWith({
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? surface,
    Color? surfaceElevated,
    Color? surfacePaper,
    Color? primary,
    Color? primaryMuted,
    Color? secondary,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textStamp,
  }) {
    return FacteurColors(
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfacePaper: surfacePaper ?? this.surfacePaper,
      primary: primary ?? this.primary,
      primaryMuted: primaryMuted ?? this.primaryMuted,
      secondary: secondary ?? this.secondary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textStamp: textStamp ?? this.textStamp,
    );
  }

  @override
  FacteurColors lerp(ThemeExtension<FacteurColors>? other, double t) {
    if (other is! FacteurColors) {
      return this;
    }
    return FacteurColors(
      backgroundPrimary:
          Color.lerp(backgroundPrimary, other.backgroundPrimary, t)!,
      backgroundSecondary:
          Color.lerp(backgroundSecondary, other.backgroundSecondary, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfacePaper: Color.lerp(surfacePaper, other.surfacePaper, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryMuted: Color.lerp(primaryMuted, other.primaryMuted, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textStamp: Color.lerp(textStamp, other.textStamp, t)!,
    );
  }

  // Static constant semantics
  static const Color sSuccess = Color(0xFF2ECC71);
  static const Color sWarning = Color(0xFFF39C12);
  static const Color sError = Color(0xFFE74C3C);
  static const Color sInfo = Color(0xFF3498DB);
}

// Définitions des Palettes
class FacteurPalettes {
  static final FacteurColors light = FacteurColors(
    backgroundPrimary: const Color(0xFFF2E8D5), // Jaune Paille / Crème
    backgroundSecondary: const Color(0xFFEBE0CC),
    surface: const Color(0xFFFDFBF7), // Papier Blanc Cassé
    surfaceElevated: const Color(0xFFFFFDF9),
    surfacePaper: const Color(0xFFFFFFFF),
    primary: const Color(0xFFD35400), // Ocre Rouge
    primaryMuted: const Color(0xFFFFE0B2),
    secondary: const Color(0xFF7F8C8D),
    success: const Color(0xFF27AE60),
    warning: const Color(0xFFD35400),
    error: const Color(0xFFC0392B),
    info: const Color(0xFF2980B9),
    textPrimary: const Color(0xFF2C2A29), // Charbon Doux
    textSecondary: const Color(0xFF5D5B5A),
    textTertiary: const Color(0xFF959392),
    textStamp: const Color(0xFFD35400).withValues(alpha: 0.8),
  );

  static final FacteurColors dark = FacteurColors(
    backgroundPrimary: const Color(0xFF101010), // Noir Charbon
    backgroundSecondary: const Color(0xFF161616),
    surface: const Color(0xFF1C1C1C), // Gris Ardoise
    surfaceElevated: const Color(0xFF242424),
    surfacePaper: const Color(0xFF2A2A2A),
    primary: const Color(0xFFC0392B), // Rouge Sceau
    primaryMuted: const Color(0xFF5A2A25),
    secondary: const Color(0xFF5D6D7E),
    success: FacteurColors.sSuccess,
    warning: FacteurColors.sWarning,
    error: FacteurColors.sError,
    info: FacteurColors.sInfo,
    textPrimary: const Color(0xFFEAEAEA), // Blanc Craie
    textSecondary: const Color(0xFFA6A6A6),
    textTertiary: const Color(0xFF606060),
    textStamp: const Color(0xFFC0392B).withValues(alpha: 0.8),
  );
}

/// Typographie Facteur - Helper classes (Stateless)
class FacteurTypography {
  FacteurTypography._();

  static TextStyle displayLarge(Color color) => GoogleFonts.fraunces(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: color,
      );

  static TextStyle displayMedium(Color color) => GoogleFonts.fraunces(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color,
      );

  static TextStyle displaySmall(Color color) => GoogleFonts.fraunces(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: color,
      );

  static TextStyle bodyLarge(Color color) => GoogleFonts.dmSans(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  static TextStyle bodyMedium(Color color) => GoogleFonts.dmSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  static TextStyle bodySmall(Color color) => GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color,
      );

  static TextStyle labelLarge(Color color) => GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: color,
      );

  static TextStyle labelMedium(Color color) => GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: color,
      );

  static TextStyle labelSmall(Color color) => GoogleFonts.dmSans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: 0.5,
        color: color,
      );

  static TextStyle stamp(Color color) => GoogleFonts.courierPrime(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0.5,
        color: color,
      );
}

class FacteurSpacing {
  FacteurSpacing._();
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space6 = 24;
  static const double space8 = 32;
}

class FacteurRadius {
  FacteurRadius._();
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double pill = 100;
  static const double full = 999;
}

class FacteurDurations {
  FacteurDurations._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}

class FacteurTheme {
  FacteurTheme._();

  static ThemeData get lightTheme =>
      _buildTheme(FacteurPalettes.light, Brightness.light);
  static ThemeData get darkTheme =>
      _buildTheme(FacteurPalettes.dark, Brightness.dark);

  static ThemeData _buildTheme(FacteurColors colors, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [colors], // Inject semantics

      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.primary,
        onPrimary: colors.textPrimary,
        secondary: colors.secondary,
        onSecondary: colors.backgroundPrimary,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        error: colors.error,
        onError: colors.textPrimary,
        // Legacy/Fallback mapping
        background: colors.backgroundPrimary,
        onBackground: colors.textPrimary,
      ),

      scaffoldBackgroundColor: colors.backgroundPrimary,

      appBarTheme: AppBarTheme(
        backgroundColor: colors.backgroundPrimary,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: FacteurTypography.displaySmall(colors.textPrimary),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.backgroundSecondary,
        selectedItemColor: colors.primary,
        unselectedItemColor: colors.textTertiary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: FacteurTypography.labelMedium(colors.textSecondary),
        unselectedLabelStyle:
            FacteurTypography.labelMedium(colors.textTertiary),
      ),

      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FacteurRadius.small),
          ),
          textStyle: FacteurTypography.labelLarge(colors.textPrimary),
          animationDuration: FacteurDurations.medium,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.primary),
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FacteurRadius.small),
          ),
          textStyle: FacteurTypography.labelLarge(colors.primary),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          textStyle: FacteurTypography.labelLarge(colors.primary),
        ),
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfacePaper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.small),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.small),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.small),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.small),
          borderSide: BorderSide(color: colors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space3,
        ),
        hintStyle: FacteurTypography.bodyMedium(colors.textTertiary),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surface,
        contentTextStyle: FacteurTypography.bodyMedium(colors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.small),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Typography
      textTheme: TextTheme(
        displayLarge: FacteurTypography.displayLarge(colors.textPrimary),
        displayMedium: FacteurTypography.displayMedium(colors.textPrimary),
        displaySmall: FacteurTypography.displaySmall(colors.textPrimary),
        bodyLarge: FacteurTypography.bodyLarge(colors.textPrimary),
        bodyMedium: FacteurTypography.bodyMedium(colors.textPrimary),
        bodySmall: FacteurTypography.bodySmall(colors.textSecondary),
        labelLarge: FacteurTypography.labelLarge(colors.textPrimary),
        labelMedium: FacteurTypography.labelMedium(colors.textSecondary),
        labelSmall: FacteurTypography.labelSmall(colors.textSecondary),
      ),
    );
  }
}

extension FacteurThemeContext on BuildContext {
  FacteurColors get facteurColors => Theme.of(this).extension<FacteurColors>()!;
}

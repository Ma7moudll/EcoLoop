import 'package:flutter/material.dart';

/// EcoLoop design tokens — preserves the original prototype's identity:
/// deep green, emerald, soft green backgrounds, white cards, dark text, blue
/// AI accent, yellow + orange for status.
abstract final class AppColors {
  static const background = Color(0xFFF5F5F9);
  static const appSurface = Color(0xFFF5F5F9);
  static const foreground = Color(0xFF0B2925);
  static const green = Color(0xFF109581);
  static const deepGreen = Color(0xFF003D31);
  static const scannerDark = Color(0xFF0E1F17);
  static const mint = Color(0xFFE9F7EF);
  static const line = Color(0xFFE3E6EC);
  static const muted = Color(0xFF6C7E79);
  static const yellow = Color(0xFFF0C808);
  static const blue = Color(0xFF2B81DC);
  static const orange = Color(0xFFE8590C);
  static const danger = Color(0xFFB43F37);
  static const white = Color(0xFFFFFFFF);

  static const card = white;
  static const iconFill = Color(0xFFD5E7FA);
  static const rewardBg = Color(0xFFEFF9F2);
  static const errorBg = Color(0xFFFBEBE8);

  /// Maps a compartment color hex (from shared policy) to a [Color].
  static Color fromHex(String hex) {
    final value = hex.replaceFirst('#', '');
    final intVal = int.tryParse(value, radix: 16) ?? 0x000000;
    return Color(0xFF000000 | intVal);
  }
}

abstract final class AppRadii {
  static const small = 10.0;
  static const medium = 14.0;
  static const large = 20.0;
  static const card = 18.0;
}

/// Loads the bundled Inter (primary) + Tajawal (Arabic) fonts and Material 3
/// theme tuned to the EcoLoop identity.
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.green,
      primary: AppColors.green,
      secondary: AppColors.blue,
      surface: AppColors.appSurface,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.appSurface,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: const TextStyle(
        fontSize: 26,
        height: 1.1,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
        letterSpacing: -0.4,
      ),
      titleLarge: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
      ),
      titleMedium: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
      ),
      bodyMedium: const TextStyle(fontSize: 13, color: AppColors.foreground),
      bodySmall: const TextStyle(fontSize: 11, color: AppColors.muted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        borderSide: const BorderSide(color: AppColors.green, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      errorStyle: const TextStyle(color: AppColors.danger, fontSize: 11),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.green,
        foregroundColor: AppColors.white,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.green,
        side: const BorderSide(color: AppColors.line),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
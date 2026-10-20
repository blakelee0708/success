import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Two [ThemeData] personas. The senior theme is the app default
/// (the role-split first screen is the senior-app entry point).
class AppTheme {
  AppTheme._();

  /// The face the design is drawn in, bundled with the app.
  ///
  /// Set on both personas rather than left to the phone: unset, Flutter draws
  /// Korean in whatever the handset ships — 삼성One here, Roboto there — and an
  /// app whose whole promise is that it is easy to read should not look
  /// different on every phone. Only 400 and 700 are bundled, so w500 and w600
  /// round to Regular and w800/w900 to Bold.
  static const fontFamily = 'Noto Sans KR';

  static ThemeData get senior {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.seniorPrimary,
          brightness: Brightness.light,
        ).copyWith(
          // Kept rather than generated: a tonal palette built from the
          // terracotta seed turns it into a muddy brown, and every filled
          // button in the app wore that instead of the colour the design names.
          primary: AppColors.seniorPrimary,
          onPrimary: Colors.white,
          surface: AppColors.seniorSurface,
          onSurface: AppColors.seniorOnSurface,
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.seniorBackground,
      // Larger defaults for senior-facing UI.
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 22),
        labelLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }

  static ThemeData get guardian {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.guardianPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.guardianPrimary,
          onPrimary: Colors.white,
          surface: AppColors.guardianSurface,
          onSurface: AppColors.guardianOnSurface,
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.guardianBackground,
    );
  }
}

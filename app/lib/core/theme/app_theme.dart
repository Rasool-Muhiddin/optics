import 'package:flutter/material.dart';

/// RTL-first theme with the bundled Arabic font.
class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'NotoNaskhArabic';
  static const Color seed = Color(0xFF0F6E8C);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: const Color(0xFFF5F7F9),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: false,
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      visualDensity: VisualDensity.compact,
    );
  }
}

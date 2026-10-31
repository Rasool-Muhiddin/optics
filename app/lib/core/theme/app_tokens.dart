import 'package:flutter/material.dart';

/// Design tokens: spacing, radii, durations. Use these instead of literal numbers.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal padding of page content inside the shell.
  static const double page = 24;
}

class AppRadius {
  const AppRadius._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;

  static final BorderRadius smAll = BorderRadius.circular(sm);
  static final BorderRadius mdAll = BorderRadius.circular(md);
  static final BorderRadius lgAll = BorderRadius.circular(lg);
  static final BorderRadius xlAll = BorderRadius.circular(xl);
}

class AppDurations {
  const AppDurations._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
}

/// Semantic tone of a badge, KPI, amount or notice.
enum Tone { neutral, primary, success, warning, danger, info }

/// Brand palette (raw values). Widgets read colours from [ColorScheme] / [AppColors], never here.
class AppPalette {
  const AppPalette._();

  // Primary: calm deep teal.
  static const Color primary = Color(0xFF0E6E8A);
  static const Color primaryDark = Color(0xFF3CB5D3);

  // Light neutrals (slate).
  static const Color lightBackground = Color(0xFFF4F6F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceMuted = Color(0xFFF1F4F8);
  static const Color lightSurfaceStrong = Color(0xFFE7ECF2);
  static const Color lightBorder = Color(0xFFE1E6ED);
  static const Color lightText = Color(0xFF0F1B2A);
  static const Color lightTextMuted = Color(0xFF5F6E80);

  // Dark neutrals.
  static const Color darkBackground = Color(0xFF0B1118);
  static const Color darkSurface = Color(0xFF121A24);
  static const Color darkSurfaceMuted = Color(0xFF17212D);
  static const Color darkSurfaceStrong = Color(0xFF1F2B39);
  static const Color darkBorder = Color(0xFF263444);
  static const Color darkText = Color(0xFFE6EDF4);
  static const Color darkTextMuted = Color(0xFF8D9CAE);

  // Sidebar (always dark, both themes).
  static const Color sidebar = Color(0xFF0F2130);
  static const Color sidebarDark = Color(0xFF0D161F);

  // Semantic.
  static const Color success = Color(0xFF15803D);
  static const Color successDark = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFB45309);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFC62828);
  static const Color dangerDark = Color(0xFFF87171);
  static const Color info = Color(0xFF1D4ED8);
  static const Color infoDark = Color(0xFF60A5FA);
}

/// Extra semantic colours that [ColorScheme] does not have.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.info,
    required this.infoContainer,
    required this.border,
    required this.surfaceMuted,
    required this.textMuted,
    required this.zebra,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarMuted,
    required this.sidebarActive,
    required this.cardShadow,
  });

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color info;
  final Color infoContainer;
  final Color border;
  final Color surfaceMuted;
  final Color textMuted;

  /// Background of every other table row.
  final Color zebra;
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarMuted;
  final Color sidebarActive;
  final List<BoxShadow> cardShadow;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? AppColors.light;

  static const light = AppColors(
    success: AppPalette.success,
    successContainer: Color(0xFFE7F6EC),
    warning: AppPalette.warning,
    warningContainer: Color(0xFFFDF3E1),
    danger: AppPalette.danger,
    dangerContainer: Color(0xFFFDECEC),
    info: AppPalette.info,
    infoContainer: Color(0xFFE8EFFD),
    border: AppPalette.lightBorder,
    surfaceMuted: AppPalette.lightSurfaceMuted,
    textMuted: AppPalette.lightTextMuted,
    zebra: Color(0xFFF8FAFC),
    sidebar: AppPalette.sidebar,
    sidebarForeground: Color(0xFFE9F1F7),
    sidebarMuted: Color(0xFF8FA6B8),
    sidebarActive: Color(0xFF1A3B52),
    cardShadow: [BoxShadow(color: Color(0x0A0F1B2A), blurRadius: 12, offset: Offset(0, 2))],
  );

  static const dark = AppColors(
    success: AppPalette.successDark,
    successContainer: Color(0xFF12301F),
    warning: AppPalette.warningDark,
    warningContainer: Color(0xFF362811),
    danger: AppPalette.dangerDark,
    dangerContainer: Color(0xFF3A1A1C),
    info: AppPalette.infoDark,
    infoContainer: Color(0xFF172846),
    border: AppPalette.darkBorder,
    surfaceMuted: AppPalette.darkSurfaceMuted,
    textMuted: AppPalette.darkTextMuted,
    zebra: Color(0xFF151E29),
    sidebar: AppPalette.sidebarDark,
    sidebarForeground: Color(0xFFE6EDF4),
    sidebarMuted: Color(0xFF7D8DA0),
    sidebarActive: Color(0xFF1B2C3C),
    cardShadow: [],
  );

  /// Foreground / background pair for a [Tone].
  ({Color fg, Color bg}) tone(Tone tone, ColorScheme scheme) => switch (tone) {
    Tone.neutral => (fg: textMuted, bg: surfaceMuted),
    Tone.primary => (fg: scheme.primary, bg: scheme.primaryContainer),
    Tone.success => (fg: success, bg: successContainer),
    Tone.warning => (fg: warning, bg: warningContainer),
    Tone.danger => (fg: danger, bg: dangerContainer),
    Tone.info => (fg: info, bg: infoContainer),
  };

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      success: c(success, other.success),
      successContainer: c(successContainer, other.successContainer),
      warning: c(warning, other.warning),
      warningContainer: c(warningContainer, other.warningContainer),
      danger: c(danger, other.danger),
      dangerContainer: c(dangerContainer, other.dangerContainer),
      info: c(info, other.info),
      infoContainer: c(infoContainer, other.infoContainer),
      border: c(border, other.border),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      textMuted: c(textMuted, other.textMuted),
      zebra: c(zebra, other.zebra),
      sidebar: c(sidebar, other.sidebar),
      sidebarForeground: c(sidebarForeground, other.sidebarForeground),
      sidebarMuted: c(sidebarMuted, other.sidebarMuted),
      sidebarActive: c(sidebarActive, other.sidebarActive),
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
    );
  }
}

/// Text helpers.
class AppText {
  const AppText._();

  /// Equal-width digits so amounts line up in columns.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Style for numbers / money (tabular digits, medium weight).
  static TextStyle numeric(BuildContext context, {TextStyle? base, FontWeight? weight}) =>
      (base ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontFeatures: tabular,
        fontWeight: weight ?? FontWeight.w500,
      );
}

import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// RTL-first light/dark themes built from the design tokens in `app_tokens.dart`.
///
/// Every component (cards, inputs, buttons, chips, tables, dialogs, tabs, snackbars…) is styled
/// here so screens use plain Material widgets and inherit the look.
class AppTheme {
  const AppTheme._();

  /// UI font (Arabic + Latin). PDFs keep using Noto Naskh Arabic (see `pdf_kit.dart`).
  static const String fontFamily = 'IBMPlexSansArabic';
  static const Color seed = AppPalette.primary;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;
    final base = ColorScheme.fromSeed(
      seedColor: isDark ? AppPalette.primaryDark : AppPalette.primary,
      brightness: brightness,
    );
    final scheme = base.copyWith(
      primary: isDark ? AppPalette.primaryDark : AppPalette.primary,
      onPrimary: isDark ? const Color(0xFF03241D) : Colors.white,
      primaryContainer: isDark ? const Color(0xFF0E3A31) : const Color(0xFFDDF3EC),
      onPrimaryContainer: isDark ? const Color(0xFFB6F0DE) : const Color(0xFF0B3D32),
      secondaryContainer: isDark ? const Color(0xFF1E2C3A) : const Color(0xFFE9EEF4),
      onSecondaryContainer: isDark ? AppPalette.darkText : AppPalette.lightText,
      tertiaryContainer: colors.warningContainer,
      onTertiaryContainer: isDark ? const Color(0xFFFDE7B0) : const Color(0xFF6B3A06),
      error: colors.danger,
      errorContainer: colors.dangerContainer,
      onErrorContainer: isDark ? const Color(0xFFFECACA) : const Color(0xFF7F1D1D),
      surface: isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
      onSurface: isDark ? AppPalette.darkText : AppPalette.lightText,
      onSurfaceVariant: colors.textMuted,
      surfaceContainerLowest: isDark ? AppPalette.darkBackground : AppPalette.lightSurface,
      surfaceContainerLow: isDark ? AppPalette.darkSurfaceMuted : const Color(0xFFF7F9FB),
      surfaceContainer: isDark ? AppPalette.darkSurfaceMuted : AppPalette.lightSurfaceMuted,
      surfaceContainerHigh: isDark ? AppPalette.darkSurfaceStrong : const Color(0xFFECF0F5),
      surfaceContainerHighest: isDark
          ? AppPalette.darkSurfaceStrong
          : AppPalette.lightSurfaceStrong,
      outline: isDark ? const Color(0xFF3A4A5C) : const Color(0xFFC5CDD8),
      outlineVariant: colors.border,
      surfaceTint: Colors.transparent,
    );

    final textTheme = _textTheme(scheme);
    final inputBorder = OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: scheme.outline.withValues(alpha: isDark ? 0.8 : 0.7)),
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.mdAll);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);
    const buttonMinSize = Size(64, 42);
    final buttonText = textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: textTheme,
      extensions: [colors],
      scaffoldBackgroundColor: isDark ? AppPalette.darkBackground : AppPalette.lightBackground,
      canvasColor: scheme.surface,
      dividerColor: colors.border,
      hintColor: colors.textMuted,
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        shape: Border(bottom: BorderSide(color: colors.border)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: colors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark ? AppPalette.darkSurfaceMuted : AppPalette.lightSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder.copyWith(borderSide: BorderSide(color: colors.border)),
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(color: scheme.primary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
        helperStyle: textTheme.bodySmall?.copyWith(color: colors.textMuted),
        errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
        prefixIconColor: colors.textMuted,
        suffixIconColor: colors.textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: buttonShape,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          textStyle: buttonText,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          foregroundColor: colors.textMuted,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: buttonShape,
          side: BorderSide(color: colors.border),
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        side: BorderSide(color: colors.border),
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.primary,
        labelStyle: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: colors.border),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: AppRadius.mdAll,
              side: BorderSide(color: colors.border),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        iconColor: colors.textMuted,
        titleTextStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: colors.textMuted),
        selectedColor: scheme.primary,
        selectedTileColor: scheme.primaryContainer,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: colors.textMuted,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: textTheme.labelLarge,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: colors.border,
        overlayColor: WidgetStatePropertyAll(scheme.primary.withValues(alpha: 0.06)),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(colors.surfaceMuted),
        headingTextStyle: textTheme.labelMedium?.copyWith(
          color: colors.textMuted,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: textTheme.bodyMedium,
        dividerThickness: 1,
        headingRowHeight: 44,
        dataRowMinHeight: 44,
        horizontalMargin: 16,
        columnSpacing: 24,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppPalette.darkSurfaceStrong : const Color(0xFF16222F),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: AppPalette.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        elevation: 4,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? AppPalette.darkSurfaceStrong : const Color(0xFF16222F),
          borderRadius: AppRadius.smAll,
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : scheme.outline,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: colors.surfaceMuted,
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(AppRadius.pill),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor: WidgetStatePropertyAll(scheme.outline.withValues(alpha: 0.5)),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: colors.textMuted,
        collapsedIconColor: colors.textMuted,
      ),
      badgeTheme: BadgeThemeData(backgroundColor: scheme.error),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final base = Typography.material2021(platform: TargetPlatform.windows).black.apply(
      fontFamily: fontFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle? s(TextStyle? t, double size, FontWeight weight, {double height = 1.4}) =>
        t?.copyWith(fontSize: size, fontWeight: weight, height: height, letterSpacing: 0);
    return base.copyWith(
      displaySmall: s(base.displaySmall, 32, FontWeight.w700, height: 1.25),
      headlineLarge: s(base.headlineLarge, 28, FontWeight.w700, height: 1.3),
      headlineMedium: s(base.headlineMedium, 24, FontWeight.w700, height: 1.3),
      headlineSmall: s(base.headlineSmall, 21, FontWeight.w700, height: 1.35),
      titleLarge: s(base.titleLarge, 18, FontWeight.w600),
      titleMedium: s(base.titleMedium, 15.5, FontWeight.w600),
      titleSmall: s(base.titleSmall, 14, FontWeight.w600),
      bodyLarge: s(base.bodyLarge, 15, FontWeight.w400, height: 1.55),
      bodyMedium: s(base.bodyMedium, 14, FontWeight.w400, height: 1.55),
      bodySmall: s(
        base.bodySmall,
        12.5,
        FontWeight.w400,
        height: 1.5,
      )?.copyWith(color: scheme.onSurfaceVariant),
      labelLarge: s(base.labelLarge, 13.5, FontWeight.w500),
      labelMedium: s(base.labelMedium, 12.5, FontWeight.w500),
      labelSmall: s(base.labelSmall, 11.5, FontWeight.w500),
    );
  }
}

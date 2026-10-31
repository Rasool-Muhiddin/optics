import 'package:flutter/material.dart';

import '../core/strings/app_strings.dart';
import 'connection_status_banner.dart';
import 'ui.dart';
import 'update_banner.dart';

/// Split layout shared by the activation and login screens: brand panel + form card.
/// Narrow windows show the form card only.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SurfaceBox(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: BrandLogo(size: 88),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(title, style: theme.textTheme.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      body: Column(
        children: [
          const ConnectionStatusBanner(),
          const UpdateBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 900) return form;
                return Row(
                  children: [
                    const SizedBox(width: 420, child: _BrandPanel()),
                    Expanded(child: form),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark brand panel (start side) with the product name and the company.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.sidebarMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.sidebarForeground),
            ),
          ),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [colors.sidebar, Color.lerp(colors.sidebar, theme.colorScheme.primary, 0.35)!],
        ),
      ),
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(size: 72),
          const Spacer(),
          Text(
            AppStrings.appTitle,
            style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppStrings.appTagline,
            style: theme.textTheme.titleSmall?.copyWith(color: colors.sidebarForeground),
          ),
          const SizedBox(height: AppSpacing.xl),
          point(Icons.people_outline, AppStrings.navPatients),
          point(Icons.point_of_sale, AppStrings.navPos),
          point(Icons.inventory_2_outlined, AppStrings.navInventory),
          point(Icons.bar_chart, AppStrings.navReports),
          const Spacer(),
          Text(
            AppStrings.companyName,
            style: theme.textTheme.labelLarge?.copyWith(color: colors.sidebarMuted),
          ),
        ],
      ),
    );
  }
}

/// Error line under a form (Arabic message from [errorMessageFor]).
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: AppRadius.mdAll),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: colors.danger),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message!,
                key: const Key('form-error'),
                style: TextStyle(color: colors.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/strings/app_strings.dart';
import '../../widgets/ui.dart';

/// Shown while the stored session is being checked.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 160),
            const SizedBox(height: AppSpacing.lg),
            Text(AppStrings.appTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppStrings.appTagline,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.of(context).textMuted),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SizedBox(width: 160, child: LinearProgressIndicator()),
            const SizedBox(height: AppSpacing.md),
            Text(AppStrings.loading, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

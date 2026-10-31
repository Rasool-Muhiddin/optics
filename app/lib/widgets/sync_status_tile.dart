import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters/formatters.dart';
import '../core/strings/app_strings.dart';
import '../services/connectivity_service.dart';
import '../services/offline_sync_service.dart';
import 'common.dart';

/// Sidebar row: last full sync of the offline copy + "sync now".
///
/// [compact] = icon only (collapsed sidebar rail); the last sync time goes in the tooltip.
class SyncStatusTile extends ConsumerWidget {
  const SyncStatusTile({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final offline = ref.watch(connectionStatusProvider).value == ConnectionStatus.offline;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final lastText = sync.lastSync == null
        ? AppStrings.notSyncedYet
        : Formatters.dateTime(sync.lastSync);

    Future<void> syncNow() async {
      try {
        final result = await ref.read(syncControllerProvider.notifier).syncNow();
        if (result != null && context.mounted) {
          showSnack(context, result.failed.isEmpty ? AppStrings.syncDone : AppStrings.syncPartial);
        }
      } catch (e) {
        if (context.mounted) showErrorSnack(context, e);
      }
    }

    final button = IconButton(
      key: const Key('sync-now'),
      tooltip: compact
          ? '${AppStrings.syncNow} — ${AppStrings.lastFullSync}: $lastText'
          : AppStrings.syncNow,
      color: colors.sidebarMuted,
      icon: sync.running
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.sync, size: 20),
      onPressed: sync.running || offline ? null : syncNow,
    );

    if (compact) {
      return Padding(
        key: const Key('sync-tile'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(child: button),
      );
    }

    return Container(
      key: const Key('sync-tile'),
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.sidebarActive.withValues(alpha: 0.6),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_sync_outlined, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sync.running ? AppStrings.syncing : AppStrings.lastFullSync,
                  style: theme.textTheme.labelMedium?.copyWith(color: colors.sidebarForeground),
                ),
                Text(
                  lastText,
                  key: const Key('sync-last'),
                  textDirection: sync.lastSync == null ? null : TextDirection.ltr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.sidebarMuted,
                    fontFeatures: AppText.tabular,
                  ),
                ),
              ],
            ),
          ),
          button,
        ],
      ),
    );
  }
}

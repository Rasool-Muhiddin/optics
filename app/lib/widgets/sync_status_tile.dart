import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters/formatters.dart';
import '../core/strings/app_strings.dart';
import '../services/connectivity_service.dart';
import '../services/offline_sync_service.dart';
import 'common.dart';

/// Sidebar row: last full sync of the offline copy + "sync now".
class SyncStatusTile extends ConsumerWidget {
  const SyncStatusTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final offline = ref.watch(connectionStatusProvider).value == ConnectionStatus.offline;
    final theme = Theme.of(context);
    return ListTile(
      key: const Key('sync-tile'),
      dense: true,
      leading: sync.running
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.cloud_sync_outlined, color: theme.colorScheme.primary),
      title: Text(sync.running ? AppStrings.syncing : AppStrings.lastFullSync),
      subtitle: Text(
        sync.lastSync == null ? AppStrings.notSyncedYet : Formatters.dateTime(sync.lastSync),
        key: const Key('sync-last'),
      ),
      trailing: IconButton(
        key: const Key('sync-now'),
        tooltip: AppStrings.syncNow,
        icon: const Icon(Icons.sync),
        onPressed: sync.running || offline
            ? null
            : () async {
                try {
                  final result = await ref.read(syncControllerProvider.notifier).syncNow();
                  if (result != null && context.mounted) {
                    showSnack(
                      context,
                      result.failed.isEmpty ? AppStrings.syncDone : AppStrings.syncPartial,
                    );
                  }
                } catch (e) {
                  if (context.mounted) showErrorSnack(context, e);
                }
              },
      ),
    );
  }
}

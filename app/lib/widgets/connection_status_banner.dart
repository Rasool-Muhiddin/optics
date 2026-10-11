import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/strings/app_strings.dart';
import '../services/connectivity_service.dart';

/// Thin bar shown while the server is unreachable (read-only mode).
class ConnectionStatusBanner extends ConsumerWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider).value ?? ConnectionStatus.unknown;
    if (status != ConnectionStatus.offline) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(AppStrings.offline, style: TextStyle(color: scheme.onErrorContainer)),
            ),
            TextButton(
              onPressed: () => ref.read(connectivityServiceProvider).checkNow(),
              child: const Text(AppStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}

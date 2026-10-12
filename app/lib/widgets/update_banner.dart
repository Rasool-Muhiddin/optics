import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/error_messages.dart';
import '../core/strings/app_strings.dart';
import '../services/update/update_service.dart';

/// "New version available" strip (red when mandatory) with "update now".
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateInfoProvider).value;
    if (info == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final bg = info.mandatory ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = info.mandatory ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Material(
      key: const Key('update-banner'),
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.system_update_alt, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${info.mandatory ? AppStrings.updateMandatory : AppStrings.updateAvailable} '
                '(${info.version})',
                style: TextStyle(color: fg),
              ),
            ),
            FilledButton.tonal(
              key: const Key('update-now'),
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => UpdateDialog(info: info),
              ),
              child: const Text(AppStrings.updateNow),
            ),
          ],
        ),
      ),
    );
  }
}

/// Release notes → download with progress → run installer (the app then closes).
class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({super.key, required this.info});

  final UpdateInfo info;

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  double? _progress;
  bool _busy = false;
  Object? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final service = ref.read(updateServiceProvider);
      final file = await service.download(
        widget.info,
        onProgress: (v) => mounted ? setState(() => _progress = v) : null,
      );
      await service.install(file);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      title: Text('${AppStrings.updateTitle} ${info.version}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (info.releaseNotes.isNotEmpty) Text(info.releaseNotes),
            const SizedBox(height: 12),
            const Text(AppStrings.updateHint),
            if (_progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(key: const Key('update-progress'), value: _progress),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  errorMessageFor(_error!),
                  key: const Key('update-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text(AppStrings.later),
        ),
        FilledButton(
          key: const Key('update-start'),
          onPressed: _busy ? null : _run,
          child: const Text(AppStrings.updateNow),
        ),
      ],
    );
  }
}

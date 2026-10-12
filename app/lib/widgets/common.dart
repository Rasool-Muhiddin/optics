import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/error_messages.dart';
import '../core/formatters/formatters.dart';
import '../core/strings/app_strings.dart';
import '../data/cache/cache_database.dart';
import '../services/connectivity_service.dart';

/// Loading / error (Arabic, with retry) / data for an [AsyncValue].
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorPanel(error: error, onRetry: onRetry),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 40),
            const SizedBox(height: 8),
            Text(errorMessageFor(error), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text(AppStrings.retry)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Screen title row with actions (inside the main layout, no AppBar).
///
/// [cacheTables] = the cache tables this screen reads: while the server is unreachable a
/// notice under the title says the data is a saved copy and when it was last refreshed.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.cacheTables = const [],
    this.offlineHint,
  });

  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final List<String> cacheTables;

  /// Extra line in the offline notice (e.g. "selling needs the server").
  final String? offlineHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ?leading,
              Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ),
          if (cacheTables.isNotEmpty || offlineHint != null)
            OfflineNotice(tables: cacheTables, hint: offlineHint),
        ],
      ),
    );
  }
}

/// Max `last_synced_at` of a set of cache tables (key = comma-joined table names).
final lastSyncedProvider = FutureProvider.autoDispose.family<DateTime?, String>(
  (ref, tables) =>
      ref.watch(cacheDatabaseProvider).lastSyncedAt(tables.split(',').where((t) => t.isNotEmpty)),
);

/// Offline-only strip: "saved copy — last updated …" (or "nothing saved yet").
class OfflineNotice extends ConsumerWidget {
  const OfflineNotice({super.key, required this.tables, this.hint});

  final List<String> tables;
  final String? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider).value;
    if (status != ConnectionStatus.offline) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final last = tables.isEmpty ? null : ref.watch(lastSyncedProvider(tables.join(','))).value;
    final lines = [
      if (tables.isNotEmpty)
        last == null
            ? AppStrings.neverSynced
            : '${AppStrings.offlineCopy} — ${AppStrings.lastSynced}: ${Formatters.dateTime(last)}',
      ?hint,
    ];
    return Container(
      key: const Key('offline-notice'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(lines.join('\n'), style: TextStyle(color: scheme.onTertiaryContainer)),
          ),
        ],
      ),
    );
  }
}

/// Small labelled value used in detail cards.
class InfoTile extends StatelessWidget {
  const InfoTile({super.key, required this.label, required this.value, this.width = 200});

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 2),
            Text(value.isEmpty ? AppStrings.none : value, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? scheme.error : null,
      behavior: SnackBarBehavior.floating,
      width: 520,
    ),
  );
}

void showErrorSnack(BuildContext context, Object error) =>
    showSnack(context, errorMessageFor(error), error: true);

Future<bool> confirmDialog(BuildContext context, String message, {String? confirmLabel}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const Key('confirm-ok'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel ?? AppStrings.confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Input formatters / validators shared by forms.
class Inputs {
  const Inputs._();

  static final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
  static final integer = [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))];
  static final signedInteger = [FilteringTextInputFormatter.allow(RegExp(r'[-0-9]'))];
  static final power = [FilteringTextInputFormatter.allow(RegExp(r'[-+0-9.]'))];

  static String? requiredText(String? v) =>
      (v == null || v.trim().isEmpty) ? AppStrings.required : null;

  static String? moneyValidator(String? v, {bool required = true}) {
    if (v == null || v.trim().isEmpty) return required ? AppStrings.required : null;
    final n = double.tryParse(v.trim());
    return (n == null || n < 0) ? AppStrings.invalidNumber : null;
  }

  static String? intValidator(String? v, {bool required = true, bool allowZero = true}) {
    if (v == null || v.trim().isEmpty) return required ? AppStrings.required : null;
    final n = int.tryParse(v.trim());
    if (n == null || (!allowZero && n == 0)) return AppStrings.invalidNumber;
    return null;
  }
}

/// Dialog shell with a title, scrollable body and save/cancel actions.
class FormDialog extends StatelessWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.child,
    required this.onSave,
    this.busy = false,
    this.error,
    this.width = 560,
    this.saveLabel,
  });

  final String title;
  final Widget child;
  final VoidCallback? onSave;
  final bool busy;
  final String? error;
  final double width;
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              child,
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    key: const Key('dialog-error'),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const Key('dialog-save'),
          onPressed: busy ? null : onSave,
          child: busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator())
              : Text(saveLabel ?? AppStrings.save),
        ),
      ],
    );
  }
}

/// Two-column responsive grid of form fields.
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.children, this.columns = 2, this.spacing = 12});

  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

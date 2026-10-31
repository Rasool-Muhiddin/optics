import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/error_messages.dart';
import '../core/formatters/formatters.dart';
import '../core/strings/app_strings.dart';
import '../data/cache/cache_database.dart';
import '../services/connectivity_service.dart';
import 'ui.dart';

export 'ui.dart';

/// Loading / error (Arabic, with retry) / data for an [AsyncValue].
///
/// [skeleton] shows a list skeleton while loading (full-page lists); otherwise a spinner.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.skeleton = false,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final bool skeleton;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: builder,
      loading: () => skeleton
          ? const SkeletonList()
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
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
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: colors.dangerContainer, shape: BoxShape.circle),
              child: Icon(Icons.error_outline, color: colors.danger, size: 28),
            ),
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                errorMessageFor(error),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(AppStrings.retry),
              ),
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
    this.subtitle,
  });

  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final List<String> cacheTables;

  /// Extra line in the offline notice (e.g. "selling needs the server").
  final String? offlineHint;

  /// Muted line under the title.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 20, AppSpacing.page, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.xs)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: theme.textTheme.headlineSmall),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  flex: 2,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: actions,
                  ),
                ),
              ],
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
    final last = tables.isEmpty ? null : ref.watch(lastSyncedProvider(tables.join(','))).value;
    final lines = [
      if (tables.isNotEmpty)
        last == null
            ? AppStrings.neverSynced
            : '${AppStrings.offlineCopy} — ${AppStrings.lastSynced}: ${Formatters.dateTime(last)}',
      ?hint,
    ];
    return Padding(
      key: const Key('offline-notice'),
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: NoticeBox(icon: Icons.history, tone: Tone.warning, message: lines.join('\n')),
    );
  }
}

/// Tinted inline notice (info / warning / danger / success).
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.tone = Tone.info,
    this.action,
  });

  final String message;
  final IconData icon;
  final Tone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context).tone(tone, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: c.fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.fg),
            ),
          ),
          ?action,
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
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: AppColors.of(context).textMuted),
            ),
            const SizedBox(height: 3),
            Text(
              value.isEmpty ? AppStrings.none : value,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final colors = AppColors.of(context);
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            color: error ? scheme.onError : AppColors.dark.success,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: error ? colors.danger : null,
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
      icon: const IconTile(icon: Icons.help_outline, tone: Tone.warning, size: 44),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message, textAlign: TextAlign.center),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
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

/// Dialog shell: header (title + close), scrollable body, footer with cancel / save.
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
    this.icon,
  });

  final String title;
  final Widget child;
  final VoidCallback? onSave;
  final bool busy;
  final String? error;
  final double width;
  final String? saveLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              IconTile(icon: icon!, size: 34),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
            IconButton(
              tooltip: AppStrings.cancel,
              icon: const Icon(Icons.close, size: 20),
              onPressed: busy ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg + 4,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              child,
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: colors.dangerContainer,
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 18, color: colors.danger),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            error!,
                            key: const Key('dialog-error'),
                            style: TextStyle(color: colors.danger),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const Key('dialog-save'),
          onPressed: busy ? null : onSave,
          child: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(saveLabel ?? AppStrings.save),
        ),
      ],
    );
  }
}

/// Responsive grid of form fields (drops columns when the dialog is narrow).
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.children, this.columns = 2, this.spacing = 12});

  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var cols = columns;
        while (cols > 1 && (constraints.maxWidth - spacing * (cols - 1)) / cols < 150) {
          cols--;
        }
        final width = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing + 4,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

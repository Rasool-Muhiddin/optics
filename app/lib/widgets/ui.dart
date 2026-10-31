import 'package:flutter/material.dart';

import '../core/formatters/formatters.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_tokens.dart';

export '../core/theme/app_tokens.dart'
    show Tone, AppSpacing, AppRadius, AppColors, AppText, AppDurations;

// ---------------------------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------------------------

/// Bordered surface card with an optional header (icon, title, subtitle, actions).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin = EdgeInsets.zero,
    this.headerDivider = true,
    this.borderColor,
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool headerDivider;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHeader = title != null || actions.isNotEmpty;
    return SurfaceBox(
      margin: margin,
      borderColor: borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    IconTile(icon: icon!, size: 32),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null) Text(title!, style: theme.textTheme.titleMedium),
                        if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
                ],
              ),
            ),
          if (hasHeader && headerDivider) const Divider(height: 1),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Rounded bordered surface (Material, so ListTiles/InkWells inside show their ink).
class SurfaceBox extends StatelessWidget {
  const SurfaceBox({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(borderRadius: AppRadius.lgAll, boxShadow: colors.cardShadow),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(
            color: borderColor ?? colors.border,
            width: borderColor == null ? 1 : 1.5,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Small rounded square holding an icon, tinted by [tone].
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.tone = Tone.primary, this.size = 40});

  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context).tone(tone, Theme.of(context).colorScheme);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(size / 4)),
      child: Icon(icon, size: size * 0.52, color: c.fg),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// KPI
// ---------------------------------------------------------------------------------------------

/// Dashboard metric: label, big value, optional hint line; tinted border when [alert].
class KpiCard extends StatefulWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.tone = Tone.primary,
    this.alert = false,
    this.onTap,
    this.width = 250,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final Tone tone;

  /// Highlights the card (danger border) — something is late/overdue/low.
  final bool alert;
  final VoidCallback? onTap;
  final double? width;

  @override
  State<KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<KpiCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final tone = widget.alert ? Tone.danger : widget.tone;
    final borderColor = widget.alert
        ? colors.danger
        : (_hover && widget.onTap != null
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : colors.border);
    final card = AnimatedContainer(
      duration: AppDurations.fast,
      width: widget.width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: borderColor, width: widget.alert ? 1.5 : 1),
        boxShadow: colors.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hover = v),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        style: theme.textTheme.labelLarge?.copyWith(color: colors.textMuted),
                      ),
                    ),
                    IconTile(icon: widget.icon, tone: tone, size: 34),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    widget.value,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.headlineSmall?.copyWith(fontFeatures: AppText.tabular),
                  ),
                ),
                if (widget.hint != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.hint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: widget.alert ? colors.danger : colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return card;
  }
}

// ---------------------------------------------------------------------------------------------
// Badges & amounts
// ---------------------------------------------------------------------------------------------

/// Pill with a dot: status / tag.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = Tone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Tone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context).tone(tone, Theme.of(context).colorScheme);
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: c.fg, fontWeight: FontWeight.w600);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 14, color: c.fg)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Status → tone mappings for every domain status (labels stay in [AppStrings]).
class StatusTones {
  const StatusTones._();

  static Tone invoice(String status) => switch (status) {
    'paid' => Tone.success,
    'partially_paid' => Tone.warning,
    'open' => Tone.danger,
    'cancelled' => Tone.neutral,
    _ => Tone.neutral,
  };

  static Tone job(String status) => switch (status) {
    'pending' => Tone.neutral,
    'lens_ordered' => Tone.info,
    'in_workshop' => Tone.warning,
    'ready' => Tone.success,
    'delivered' => Tone.primary,
    'cancelled' => Tone.neutral,
    _ => Tone.neutral,
  };

  static Tone order(String status) => switch (status) {
    'pending' => Tone.neutral,
    'ordered' => Tone.info,
    'partially_received' => Tone.warning,
    'received' => Tone.success,
    _ => Tone.neutral,
  };

  static Tone payment(String status) => switch (status) {
    'paid' => Tone.success,
    'partial' => Tone.warning,
    'unpaid' => Tone.danger,
    _ => Tone.neutral,
  };

  static Tone patient(String status) => switch (status) {
    'new' => Tone.info,
    'exam_done' => Tone.primary,
    'lens_selected' => Tone.warning,
    'in_job' => Tone.warning,
    'delivered' => Tone.success,
    _ => Tone.neutral,
  };

  static Tone referral(String status) => switch (status) {
    'sent' => Tone.info,
    'received' => Tone.primary,
    'in_progress' => Tone.warning,
    'completed' => Tone.success,
    'rejected' => Tone.danger,
    _ => Tone.neutral,
  };

  static Tone link(String status) => switch (status) {
    'accepted' => Tone.success,
    'pending' => Tone.warning,
    'rejected' => Tone.danger,
    _ => Tone.neutral,
  };
}

/// Money amount (formatted by [Formatters.money]): LTR, tabular digits, optional tone.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.tone,
    this.style,
    this.bold = false,
    this.textAlign,
  });

  final Object? value;
  final Tone? tone;
  final TextStyle? style;
  final bool bold;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tone == null ? null : AppColors.of(context).tone(tone!, scheme).fg;
    return Text(
      Formatters.money(value),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
      style: AppText.numeric(
        context,
        base: style,
        weight: bold ? FontWeight.w700 : FontWeight.w500,
      ).copyWith(color: color),
    );
  }
}

/// Label + value pair in a summary line (e.g. totals): `المجموع ........ 125,000 د.ع`.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.value,
    this.tone,
    this.emphasize = false,
  });

  final String label;
  final Object? value;
  final Tone? tone;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasize ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: style?.copyWith(color: emphasize ? null : AppColors.of(context).textMuted),
            ),
          ),
          MoneyText(value, tone: tone, style: style, bold: emphasize),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------------------------

/// Friendly empty state: icon, title, optional message and action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.title = AppStrings.noData,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 72,
              height: compact ? 48 : 72,
              decoration: BoxDecoration(color: colors.surfaceMuted, shape: BoxShape.circle),
              child: Icon(icon, size: compact ? 24 : 34, color: colors.textMuted),
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: AppSpacing.lg), action!],
          ],
        ),
      ),
    );
  }
}

/// Pulsing placeholder block (skeleton loading).
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = AppRadius.sm});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(colors.surfaceMuted, scheme.surfaceContainerHighest, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Skeleton of a list/table: [rows] lines of placeholder cells.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rows = 6,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.sm),
  });

  final int rows;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStrings.loading,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        child: Column(
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    const SkeletonBox(width: 36, height: 36, radius: 18),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: i.isEven ? 0.45 : 0.35,
                            child: const SkeletonBox(height: 13),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FractionallySizedBox(
                            widthFactor: i.isEven ? 0.7 : 0.6,
                            child: const SkeletonBox(height: 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    const SkeletonBox(width: 90, height: 13),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------------------------

/// Toolbar holding search + filters for a list screen.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.children, this.trailing});

  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Data table
// ---------------------------------------------------------------------------------------------

/// One column of a [DataTableHeader] / [DataRowView].
class TableCol {
  const TableCol(
    this.label, {
    this.flex = 2,
    this.numeric = false,
    this.center = false,
    this.width,
  });

  final String label;
  final int flex;

  /// Numbers / money: aligned to the end so digits line up.
  final bool numeric;
  final bool center;

  /// Fixed width instead of [flex].
  final double? width;

  AlignmentDirectional get alignment => numeric
      ? AlignmentDirectional.centerEnd
      : (center ? AlignmentDirectional.center : AlignmentDirectional.centerStart);
}

const EdgeInsets _cellPadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.lg,
  vertical: AppSpacing.md,
);

Widget _cells(List<TableCol> columns, List<Widget> cells) => Row(
  children: [
    for (var i = 0; i < cells.length && i < columns.length; i++)
      columns[i].width != null
          ? SizedBox(
              width: columns[i].width,
              child: Align(alignment: columns[i].alignment, child: cells[i]),
            )
          : Expanded(
              flex: columns[i].flex,
              child: Align(alignment: columns[i].alignment, child: cells[i]),
            ),
  ],
);

/// Table header row (place it above the scrolling rows so it stays put = sticky header).
///
/// Columns with an index in [sortable] are clickable; [sortColumn]/[ascending] show the arrow.
class DataTableHeader extends StatelessWidget {
  const DataTableHeader({
    super.key,
    required this.columns,
    this.sortable = const {},
    this.sortColumn,
    this.ascending = true,
    this.onSort,
    this.topRadius = true,
  });

  final List<TableCol> columns;
  final Set<int> sortable;
  final int? sortColumn;
  final bool ascending;
  final ValueChanged<int>? onSort;
  final bool topRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: colors.textMuted,
      fontWeight: FontWeight.w600,
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 11),
      child: _cells(columns, [
        for (var i = 0; i < columns.length; i++)
          sortable.contains(i) && onSort != null
              ? InkWell(
                  borderRadius: AppRadius.smAll,
                  onTap: () => onSort!(i),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          columns[i].label,
                          style: style,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        sortColumn == i
                            ? (ascending ? Icons.arrow_upward : Icons.arrow_downward)
                            : Icons.unfold_more,
                        size: 14,
                        color: sortColumn == i ? theme.colorScheme.primary : colors.textMuted,
                      ),
                    ],
                  ),
                )
              : Text(
                  columns[i].label,
                  style: style,
                  overflow: TextOverflow.ellipsis,
                  textAlign: columns[i].numeric ? TextAlign.end : null,
                ),
      ]),
    );
  }
}

/// One table row: zebra background, hover highlight, bottom separator.
class DataRowView extends StatefulWidget {
  const DataRowView({
    super.key,
    required this.columns,
    required this.cells,
    this.index = 0,
    this.onTap,
    this.muted = false,
    this.accent,
  });

  final List<TableCol> columns;
  final List<Widget> cells;
  final int index;
  final VoidCallback? onTap;

  /// Greyed (inactive / cancelled).
  final bool muted;

  /// Coloured start edge (e.g. danger for late rows).
  final Color? accent;

  @override
  State<DataRowView> createState() => _DataRowViewState();
}

class _DataRowViewState extends State<DataRowView> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final bg = _hover
        ? theme.colorScheme.primary.withValues(alpha: 0.05)
        : (widget.muted
              ? colors.surfaceMuted
              : (widget.index.isOdd ? colors.zebra : theme.colorScheme.surface));
    return Material(
      color: bg,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (v) => setState(() => _hover = v),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.7)),
              right: widget.accent == null
                  ? BorderSide.none
                  : BorderSide(color: widget.accent!, width: 3),
            ),
          ),
          padding: _cellPadding,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: widget.muted ? colors.textMuted : null),
            child: _cells(widget.columns, widget.cells),
          ),
        ),
      ),
    );
  }
}

/// Bordered container for a header + rows (`Column`) or header + `Expanded(ListView)`.
class TableFrame extends StatelessWidget {
  const TableFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SurfaceBox(child: child);
  }
}

/// Footer under a table: row count + optional "load more".
class TableFooter extends StatelessWidget {
  const TableFooter({super.key, required this.count, this.onLoadMore, this.extra});

  final int count;
  final VoidCallback? onLoadMore;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.of(context).surfaceMuted),
      child: Row(
        children: [
          Text('${AppStrings.rowsShown}: $count', style: theme.textTheme.bodySmall),
          const Spacer(),
          ?extra,
          if (onLoadMore != null)
            TextButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more, size: 18),
              label: const Text(AppStrings.loadMore),
            ),
        ],
      ),
    );
  }
}

/// Sticky-header table of [items]: header fixed, rows scroll, optional client-side sort.
///
/// Sorting only reorders the rows already loaded (display only).
class AppDataTable<T> extends StatefulWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.items,
    required this.cells,
    this.rowKey,
    this.onTap,
    this.sortKeys = const {},
    this.muted,
    this.accent,
    this.footer,
    this.shrinkWrap = false,
  });

  final List<TableCol> columns;
  final List<T> items;
  final List<Widget> Function(T item) cells;
  final Key Function(T item)? rowKey;
  final void Function(T item)? onTap;

  /// Column index → sort value.
  final Map<int, Comparable<Object?> Function(T item)> sortKeys;
  final bool Function(T item)? muted;
  final Color? Function(T item)? accent;
  final Widget? footer;

  /// Inside an outer scroll view (no own scrolling, header not sticky).
  final bool shrinkWrap;

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  int? _sort;
  bool _asc = true;

  List<T> get _rows {
    final key = _sort == null ? null : widget.sortKeys[_sort];
    if (key == null) return widget.items;
    final rows = [...widget.items];
    rows.sort((a, b) {
      final r = Comparable.compare(key(a), key(b));
      return _asc ? r : -r;
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    Widget row(int i) {
      final item = rows[i];
      return DataRowView(
        key: widget.rowKey?.call(item),
        columns: widget.columns,
        cells: widget.cells(item),
        index: i,
        onTap: widget.onTap == null ? null : () => widget.onTap!(item),
        muted: widget.muted?.call(item) ?? false,
        accent: widget.accent?.call(item),
      );
    }

    final header = DataTableHeader(
      columns: widget.columns,
      sortable: widget.sortKeys.keys.toSet(),
      sortColumn: _sort,
      ascending: _asc,
      onSort: (i) => setState(() {
        if (_sort == i) {
          _asc = !_asc;
        } else {
          _sort = i;
          _asc = true;
        }
      }),
    );
    return TableFrame(
      child: Column(
        mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (widget.shrinkWrap)
            for (var i = 0; i < rows.length; i++) row(i)
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                itemBuilder: (context, i) => row(i),
              ),
            ),
          ?widget.footer,
        ],
      ),
    );
  }
}

/// Avatar with the first letter of a name.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 36, this.tone = Tone.primary});

  final String name;
  final double size;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context).tone(tone, Theme.of(context).colorScheme);
    final trimmed = name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.bg, shape: BoxShape.circle),
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.characters.first,
        style: TextStyle(color: c.fg, fontWeight: FontWeight.w700, fontSize: size * 0.42),
      ),
    );
  }
}

/// Two-line cell: primary text + muted secondary line.
class TwoLineCell extends StatelessWidget {
  const TwoLineCell({super.key, required this.title, this.subtitle, this.leading});

  final String title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(subtitle!, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
      ],
    );
    if (leading == null) return text;
    return Row(
      children: [
        leading!,
        const SizedBox(width: AppSpacing.md),
        Flexible(child: text),
      ],
    );
  }
}

/// Number cell: LTR + tabular digits.
class NumText extends StatelessWidget {
  const NumText(this.text, {super.key, this.color, this.bold = false});

  final String text;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textDirection: TextDirection.ltr,
    style: AppText.numeric(
      context,
      weight: bold ? FontWeight.w700 : FontWeight.w500,
    ).copyWith(color: color),
  );
}

/// Group heading inside a form ("بيانات المراجع"…), with optional description.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    this.description,
    required this.child,
    this.icon,
    this.actions = const [],
    this.titleKey,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final Widget child;

  /// Buttons at the end of the heading line (e.g. "add line").
  final List<Widget> actions;

  /// Key of the title [Text] (for tests that look the heading up).
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(title, key: titleKey, style: theme.textTheme.titleSmall),
              const SizedBox(width: AppSpacing.md),
              const Expanded(child: Divider()),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                ...actions,
              ],
            ],
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(description!, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

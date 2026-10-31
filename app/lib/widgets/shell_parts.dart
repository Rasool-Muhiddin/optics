import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../services/connectivity_service.dart';
import '../services/ui_prefs.dart';
import 'connection_status_banner.dart';
import 'sync_status_tile.dart';
import 'ui.dart';
import 'update_banner.dart';

/// Windows narrower than this always show the sidebar as an icon rail.
const double kRailBreakpoint = 1100;
const double kSidebarWidth = 252;
const double kRailWidth = 76;

final ThemeData _sidebarTheme = AppTheme.dark();

/// One destination in a [ShellSidebar].
class ShellDestination {
  const ShellDestination({required this.path, required this.label, required this.icon, this.group});

  final String path;
  final String label;
  final IconData icon;

  /// Heading shown above the first item of each group (null = no heading).
  final String? group;
}

/// Layout shared by the lab and doctor shells: sidebar (start side) + top bar + content.
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({
    super.key,
    required this.sidebarBuilder,
    required this.topBar,
    required this.child,
  });

  final Widget Function(bool collapsed) sidebarBuilder;
  final Widget topBar;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userCollapsed = ref.watch(sidebarCollapsedProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final collapsed = userCollapsed || constraints.maxWidth < kRailBreakpoint;
        return Scaffold(
          body: Row(
            children: [
              // The sidebar is always dark: render it with the dark theme.
              Theme(data: _sidebarTheme, child: sidebarBuilder(collapsed)),
              Expanded(
                child: Column(
                  children: [
                    topBar,
                    const ConnectionStatusBanner(),
                    const UpdateBanner(),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Dark sidebar: brand header, grouped destinations with an active indicator, footer.
class ShellSidebar extends ConsumerWidget {
  const ShellSidebar({
    super.key,
    required this.collapsed,
    required this.header,
    required this.destinations,
    required this.isSelected,
    required this.onSelect,
    this.accent,
  });

  final bool collapsed;
  final Widget header;
  final List<ShellDestination> destinations;
  final bool Function(ShellDestination d) isSelected;
  final void Function(ShellDestination d) onSelect;

  /// Active indicator colour (defaults to the primary colour).
  final Color? accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final children = <Widget>[];
    String? lastGroup;
    for (final d in destinations) {
      if (d.group != null && d.group != lastGroup) {
        children.add(
          collapsed
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: 20),
                  child: Divider(),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, AppSpacing.lg, 20, AppSpacing.xs),
                  child: Text(
                    d.group!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.sidebarMuted,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
        );
      }
      lastGroup = d.group;
      children.add(
        _NavTile(
          key: Key('nav-${d.path}'),
          destination: d,
          selected: isSelected(d),
          collapsed: collapsed,
          accent: accent ?? theme.colorScheme.primary,
          onTap: () => onSelect(d),
        ),
      );
    }

    return AnimatedContainer(
      duration: AppDurations.normal,
      curve: Curves.easeOut,
      width: collapsed ? kRailWidth : kSidebarWidth,
      color: colors.sidebar,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: children,
              ),
            ),
            Divider(height: 1, color: colors.sidebarActive),
            SyncStatusTile(compact: collapsed),
            _CollapseButton(collapsed: collapsed),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    super.key,
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.accent,
    required this.onTap,
  });

  final ShellDestination destination;
  final bool selected;
  final bool collapsed;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final selected = widget.selected;
    final fg = selected ? Colors.white : (_hover ? colors.sidebarForeground : colors.sidebarMuted);
    final bg = selected
        ? colors.sidebarActive
        : (_hover ? colors.sidebarActive.withValues(alpha: 0.5) : Colors.transparent);
    final tile = Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 12 : 12, vertical: 2),
      child: Material(
        color: bg,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hover = v),
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                // Active indicator bar on the start edge.
                AnimatedContainer(
                  duration: AppDurations.fast,
                  width: 3,
                  height: selected ? 20 : 0,
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                Expanded(
                  child: widget.collapsed
                      ? Center(
                          child: Icon(
                            widget.destination.icon,
                            size: 21,
                            color: selected ? widget.accent : fg,
                          ),
                        )
                      : Row(
                          children: [
                            const SizedBox(width: 11),
                            Icon(
                              widget.destination.icon,
                              size: 20,
                              color: selected ? widget.accent : fg,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                widget.destination.label,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: fg,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.collapsed
        ? Tooltip(message: widget.destination.label, preferBelow: false, child: tile)
        : tile;
  }
}

class _CollapseButton extends ConsumerWidget {
  const _CollapseButton({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      child: Align(
        alignment: collapsed ? Alignment.center : AlignmentDirectional.centerEnd,
        child: IconButton(
          key: const Key('sidebar-collapse'),
          tooltip: collapsed ? AppStrings.expandSidebar : AppStrings.collapseSidebar,
          color: colors.sidebarMuted,
          // RTL: the sidebar is on the right, so "collapse" points right.
          icon: Icon(
            collapsed ? Icons.keyboard_double_arrow_left : Icons.keyboard_double_arrow_right,
          ),
          onPressed: () => ref.read(sidebarCollapsedProvider.notifier).toggle(),
        ),
      ),
    );
  }
}

/// Sidebar brand block: the Tera "T" mark + title + subtitle (mark only when collapsed).
class SidebarBrand extends StatelessWidget {
  const SidebarBrand({
    super.key,
    required this.collapsed,
    required this.title,
    required this.subtitle,
    this.titleKey,
  });

  final bool collapsed;
  final String title;
  final String subtitle;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final mark = BrandMark(size: collapsed ? 36 : 40);
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.sidebarActive)),
      ),
      child: collapsed
          ? Center(
              child: Tooltip(message: title, child: mark),
            )
          : Row(
              children: [
                mark,
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        key: titleKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: colors.sidebarMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Top bar: page title (+ icon), quick-jump search, connection pill, theme switch, user menu.
class ShellTopBar extends StatelessWidget {
  const ShellTopBar({
    super.key,
    required this.title,
    this.icon,
    this.search,
    this.trailing = const [],
  });

  final String title;
  final IconData? icon;
  final Widget? search;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page - 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              title,
              key: const Key('topbar-title'),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const Spacer(),
          if (search != null) ...[search!, const SizedBox(width: AppSpacing.md)],
          const ConnectionPill(),
          const SizedBox(width: AppSpacing.xs),
          const ThemeModeButton(),
          ...trailing,
        ],
      ),
    );
  }
}

/// "متصل / غير متصل" pill (server reachability).
class ConnectionPill extends ConsumerWidget {
  const ConnectionPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider).value;
    if (status == null || status == ConnectionStatus.unknown) return const SizedBox.shrink();
    final online = status != ConnectionStatus.offline;
    return StatusBadge(
      key: const Key('connection-pill'),
      label: online ? AppStrings.onlineShort : AppStrings.offlineShort,
      tone: online ? Tone.success : Tone.danger,
      icon: online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
      dense: true,
    );
  }
}

/// Light / dark / system switch.
class ThemeModeButton extends ConsumerWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final icon = switch (mode) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };
    return PopupMenuButton<ThemeMode>(
      key: const Key('theme-mode'),
      tooltip: AppStrings.themeLabel,
      icon: Icon(icon, size: 20),
      initialValue: mode,
      position: PopupMenuPosition.under,
      onSelected: (m) => ref.read(themeModeProvider.notifier).set(m),
      itemBuilder: (_) => [
        for (final (m, label, i) in [
          (ThemeMode.light, AppStrings.themeLight, Icons.light_mode_outlined),
          (ThemeMode.dark, AppStrings.themeDark, Icons.dark_mode_outlined),
          (ThemeMode.system, AppStrings.themeSystem, Icons.brightness_auto_outlined),
        ])
          CheckedPopupMenuItem(
            value: m,
            checked: m == mode,
            child: Row(children: [Icon(i, size: 18), const SizedBox(width: 10), Text(label)]),
          ),
      ],
    );
  }
}

/// Top-bar user chip: avatar + name + role, opening a menu with account info and logout.
class UserMenuButton extends StatelessWidget {
  const UserMenuButton({
    super.key,
    required this.name,
    required this.role,
    this.details = const [],
    required this.onLogout,
    this.tone = Tone.primary,
  });

  final String name;
  final String role;

  /// Extra lines in the menu header (lab, plan…).
  final List<String> details;
  final VoidCallback onLogout;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return PopupMenuButton<String>(
      key: const Key('user-menu'),
      tooltip: AppStrings.accountInfo,
      position: PopupMenuPosition.under,
      onSelected: (v) {
        if (v == 'logout') onLogout();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleSmall),
              Text(role, style: theme.textTheme.bodySmall),
              for (final d in details) Text(d, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: colors.danger),
              const SizedBox(width: 10),
              Text(AppStrings.logout, style: TextStyle(color: colors.danger)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InitialsAvatar(name: name, size: 34, tone: tone),
            const SizedBox(width: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    role,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.expand_more, size: 18, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Top-bar search box that jumps to a section by name.
class QuickJumpField extends StatelessWidget {
  const QuickJumpField({super.key, required this.destinations, required this.onSelect});

  final List<ShellDestination> destinations;
  final void Function(ShellDestination d) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 280,
      height: 38,
      child: Autocomplete<ShellDestination>(
        displayStringForOption: (d) => d.label,
        optionsBuilder: (value) {
          final q = value.text.trim();
          if (q.isEmpty) return destinations;
          return destinations.where((d) => d.label.contains(q));
        },
        onSelected: (d) {
          FocusManager.instance.primaryFocus?.unfocus();
          onSelect(d);
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
          key: const Key('quick-jump'),
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onSubmit(),
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: AppStrings.quickSearch,
            prefixIcon: const Icon(Icons.search, size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            fillColor: AppColors.of(context).surfaceMuted,
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.mdAll,
              borderSide: BorderSide(color: AppColors.of(context).border),
            ),
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 6,
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.mdAll,
              side: BorderSide(color: AppColors.of(context).border),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
              child: options.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(AppStrings.quickSearchEmpty),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      shrinkWrap: true,
                      children: [
                        for (final d in options)
                          ListTile(
                            dense: true,
                            leading: Icon(d.icon, size: 20),
                            title: Text(d.label),
                            onTap: () => onSelected(d),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

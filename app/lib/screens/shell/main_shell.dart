import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../models/session.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/shell_parts.dart';
import 'nav_items.dart';

/// Main layout: sidebar (on the right, RTL) + top bar + the current screen.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final items = navItems.where((i) => i.visibleTo(session)).toList();
    final current = navItemFor(location) ?? navSectionFor(location);
    final destinations = Sidebar.destinationsFor(items);
    final expires = session.plan.expiresOn;

    return ShellScaffold(
      sidebarBuilder: (collapsed) =>
          Sidebar(session: session, location: location, collapsed: collapsed),
      topBar: ShellTopBar(
        title: current?.label ?? AppStrings.home,
        icon: current?.icon,
        search: QuickJumpField(destinations: destinations, onSelect: (d) => context.go(d.path)),
        trailing: [
          const SizedBox(width: AppSpacing.xs),
          UserMenuButton(
            name: session.user.displayName,
            role: Sidebar.roleLabel(session.membership),
            details: [
              session.lab.name,
              expires == null
                  ? session.plan.name
                  : '${session.plan.name} — ${AppStrings.homePlanExpires} ${Formatters.date(expires)}',
            ],
            onLogout: () => Sidebar.logout(context, ref),
          ),
          IconButton(
            key: const Key('logout-button'),
            tooltip: AppStrings.logout,
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => Sidebar.logout(context, ref),
          ),
        ],
      ),
      child: child,
    );
  }
}

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, required this.session, required this.location, this.collapsed = false});

  final Session session;
  final String location;
  final bool collapsed;

  static String roleLabel(Membership m) => m.isOwner ? AppStrings.roleOwner : AppStrings.roleStaff;

  static const Map<NavGroup, String> _groupLabels = {
    NavGroup.main: AppStrings.navGroupMain,
    NavGroup.stock: AppStrings.navGroupStock,
    NavGroup.admin: AppStrings.navGroupAdmin,
  };

  /// Visible items grouped (main → stock → admin), keeping their order inside a group.
  static List<ShellDestination> destinationsFor(List<NavItem> items) => [
    for (final g in NavGroup.values)
      for (final i in items.where((i) => i.group == g))
        ShellDestination(
          path: i.path,
          label: i.label,
          icon: i.icon,
          group: g == NavGroup.main ? null : _groupLabels[g],
        ),
  ];

  static Future<void> logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const IconTile(icon: Icons.logout, tone: Tone.danger, size: 44),
        content: const Text(AppStrings.logoutConfirm, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            key: const Key('logout-confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.of(context).danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.logout),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = navItems.where((i) => i.visibleTo(session)).toList();
    final section = navSectionFor(location);
    return ShellSidebar(
      collapsed: collapsed,
      header: SidebarBrand(
        collapsed: collapsed,
        title: session.lab.name,
        titleKey: const Key('sidebar-lab-name'),
        subtitle: AppStrings.appTitle,
      ),
      destinations: destinationsFor(items),
      isSelected: (d) => d.path == location || section?.path == d.path,
      onSelect: (d) => context.go(d.path),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/strings/app_strings.dart';
import '../../models/session.dart';
import '../../services/auth_controller.dart';
import '../../widgets/connection_status_banner.dart';
import 'nav_items.dart';

/// Main layout: sidebar (on the right, RTL) + the current screen.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    return Scaffold(
      body: Row(
        children: [
          Sidebar(session: session, location: location),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                const ConnectionStatusBanner(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, required this.session, required this.location});

  final Session session;
  final String location;

  static String roleLabel(Membership m) => m.isOwner ? AppStrings.roleOwner : AppStrings.roleStaff;

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text(AppStrings.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            key: const Key('logout-confirm'),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = navItems.where((i) => i.visibleTo(session)).toList();

    return SizedBox(
      width: 240,
      child: Material(
        color: scheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: scheme.primary,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.lab.name,
                    key: const Key('sidebar-lab-name'),
                    style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.appTitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final item in items)
                    ListTile(
                      key: Key('nav-${item.path}'),
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      selected: item.path == location,
                      selectedTileColor: scheme.primaryContainer,
                      dense: true,
                      onTap: () => context.go(item.path),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(session.user.displayName, overflow: TextOverflow.ellipsis),
              subtitle: Text(roleLabel(session.membership)),
              trailing: IconButton(
                key: const Key('logout-button'),
                tooltip: AppStrings.logout,
                icon: const Icon(Icons.logout),
                onPressed: () => _logout(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_status_banner.dart';

/// Doctor mode layout: its own sidebar (referrals, labs) — no lab sections at all.
class DoctorShell extends ConsumerWidget {
  const DoctorShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _items = [
    (path: AppRoutes.doctorHome, label: AppStrings.navDoctorReferrals, icon: Icons.send_outlined),
    (path: AppRoutes.doctorLabs, label: AppStrings.navDoctorLabs, icon: Icons.store_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(doctorSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 240,
            child: Material(
              color: scheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: scheme.tertiary,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.doctor.fullName,
                          key: const Key('doctor-sidebar-name'),
                          style: theme.textTheme.titleMedium?.copyWith(color: scheme.onTertiary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppStrings.doctorMode,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onTertiary),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final item in _items)
                          ListTile(
                            key: Key('nav-${item.path}'),
                            leading: Icon(item.icon),
                            title: Text(item.label),
                            dense: true,
                            selected: location == item.path,
                            selectedTileColor: scheme.tertiaryContainer,
                            onTap: () => context.go(item.path),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.medical_services_outlined)),
                    title: Text(session.user.displayName, overflow: TextOverflow.ellipsis),
                    subtitle: Text(session.doctor.clinicName),
                    trailing: IconButton(
                      key: const Key('logout-button'),
                      tooltip: AppStrings.logout,
                      icon: const Icon(Icons.logout),
                      onPressed: () async {
                        if (await confirmDialog(context, AppStrings.logoutConfirm)) {
                          await ref.read(authControllerProvider.notifier).logout();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
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

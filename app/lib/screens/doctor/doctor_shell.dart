import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/shell_parts.dart';

/// Doctor mode layout: its own sidebar (referrals, labs) — no lab sections at all.
class DoctorShell extends ConsumerWidget {
  const DoctorShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _items = [
    ShellDestination(
      path: AppRoutes.doctorHome,
      label: AppStrings.navDoctorReferrals,
      icon: Icons.send_outlined,
    ),
    ShellDestination(
      path: AppRoutes.doctorLabs,
      label: AppStrings.navDoctorLabs,
      icon: Icons.store_outlined,
    ),
  ];

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (await confirmDialog(context, AppStrings.logoutConfirm, confirmLabel: AppStrings.logout)) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(doctorSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final current = _items.where((i) => i.path == location).firstOrNull ?? _items.first;
    final colors = AppColors.of(context);
    return ShellScaffold(
      sidebarBuilder: (collapsed) => ShellSidebar(
        collapsed: collapsed,
        accent: colors.success,
        header: SidebarBrand(
          collapsed: collapsed,
          title: session.doctor.fullName,
          titleKey: const Key('doctor-sidebar-name'),
          subtitle: AppStrings.doctorMode,
        ),
        destinations: _items,
        isSelected: (d) => d.path == location,
        onSelect: (d) => context.go(d.path),
      ),
      topBar: ShellTopBar(
        title: current.label,
        icon: current.icon,
        trailing: [
          const SizedBox(width: AppSpacing.xs),
          UserMenuButton(
            name: session.user.displayName,
            role: AppStrings.doctorMode,
            details: [if (session.doctor.clinicName.isNotEmpty) session.doctor.clinicName],
            tone: Tone.success,
            onLogout: () => _logout(context, ref),
          ),
          IconButton(
            key: const Key('logout-button'),
            tooltip: AppStrings.logout,
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => _logout(context, ref),
          ),
        ],
      ),
      child: child,
    );
  }
}

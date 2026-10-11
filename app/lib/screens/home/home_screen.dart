import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../services/auth_controller.dart';
import '../shell/main_shell.dart';

/// Landing page inside the main layout. The P8 dashboard replaces its body.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final state = ref.watch(authControllerProvider).value;
    if (session == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final expires = session.plan.expiresOn;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('${AppStrings.welcome}، ${session.user.displayName}', style: textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (state is LoggedIn && state.restoredOffline)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(AppStrings.sessionOffline, style: textTheme.bodyMedium),
          ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.store_outlined),
                title: const Text(AppStrings.homeLab),
                subtitle: Text(session.lab.name),
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text(AppStrings.homeRole),
                subtitle: Text(Sidebar.roleLabel(session.membership)),
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text(AppStrings.homePlan),
                subtitle: Text(
                  expires == null
                      ? session.plan.name
                      : '${session.plan.name} — ${AppStrings.homePlanExpires} '
                            '${Formatters.date(expires)}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

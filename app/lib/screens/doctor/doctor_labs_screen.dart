import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/doctors_repository.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import 'doctor_providers.dart';
import 'links_panel.dart';

/// Doctor mode: the doctor's link code and linked labs (request / accept / revoke).
class DoctorLabsScreen extends ConsumerWidget {
  const DoctorLabsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(doctorSessionProvider);
    final repo = ref.read(doctorRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: AppStrings.navDoctorLabs,
          cacheTables: [CacheTables.doctorSideLinks],
        ),
        Expanded(
          child: AsyncView(
            value: ref.watch(doctorLinksProvider),
            onRetry: () => ref.invalidate(doctorLinksProvider),
            builder: (links) => LinksPanel(
              side: 'doctor',
              code: session?.doctor.linkCode,
              links: links,
              onRequest: (code) async {
                try {
                  await repo.requestLink(code);
                  invalidateDoctor(ref);
                } catch (e) {
                  if (context.mounted) showErrorSnack(context, e);
                }
              },
              onAction: (link, action) async {
                try {
                  await repo.linkAction(link.id, action);
                  invalidateDoctor(ref);
                } catch (e) {
                  if (context.mounted) showErrorSnack(context, e);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

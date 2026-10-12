import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/doctors_repository.dart';
import '../../models/doctors.dart';
import '../../widgets/common.dart';
import '../../widgets/patient_picker.dart';
import '../../widgets/referral_view.dart';
import '../doctor/doctor_providers.dart';
import '../patients/exam_dialogs.dart' show askVoidReason;
import '../patients/patients_providers.dart';

/// One referral in the lab: receive, accept (new or existing patient file), reject, complete.
class ReferralDetailScreen extends ConsumerWidget {
  const ReferralDetailScreen({super.key, required this.referralId});

  final int referralId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(referralsRepositoryProvider);

    Future<void> act(String action, [Map<String, dynamic> body = const {}]) async {
      try {
        final r = await repo.act(referralId, action, body);
        invalidateReferrals(ref, referralId);
        if (action == 'accept') ref.invalidate(patientListProvider);
        if (action == 'accept' && r.patientId != null && context.mounted) {
          showSnack(context, AppStrings.saved);
        }
      } catch (e) {
        if (context.mounted) showErrorSnack(context, e);
      }
    }

    Future<void> accept() async {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text(AppStrings.acceptReferral),
          children: [
            SimpleDialogOption(
              key: const Key('accept-new-patient'),
              onPressed: () => Navigator.of(context).pop('new'),
              child: const Text(AppStrings.acceptIntoNew),
            ),
            SimpleDialogOption(
              key: const Key('accept-existing-patient'),
              onPressed: () => Navigator.of(context).pop('existing'),
              child: const Text(AppStrings.acceptIntoExisting),
            ),
          ],
        ),
      );
      if (choice == null || !context.mounted) return;
      if (choice == 'new') return act('accept');
      final patient = await pickPatient(context);
      if (patient != null) await act('accept', {'patient': patient.id});
    }

    return AsyncView(
      value: ref.watch(labReferralProvider(referralId)),
      onRetry: () => ref.invalidate(labReferralProvider(referralId)),
      builder: (r) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          PageHeader(
            title: '${AppStrings.referral}: ${r.patientName}',
            leading: IconButton(
              tooltip: AppStrings.back,
              icon: const Icon(Icons.arrow_forward),
              onPressed: () => context.go(AppRoutes.referrals),
            ),
            actions: [
              if (r.status == ReferralStatuses.sent)
                OutlinedButton(
                  key: const Key('referral-receive'),
                  onPressed: () => act('receive'),
                  child: const Text(AppStrings.markReceived),
                ),
              if (r.isOpen) ...[
                FilledButton.icon(
                  key: const Key('referral-accept'),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text(AppStrings.acceptReferral),
                  onPressed: accept,
                ),
                TextButton(
                  key: const Key('referral-reject'),
                  onPressed: () async {
                    final reason = await askVoidReason(context);
                    if (reason != null) await act('reject', {'reason': reason});
                  },
                  child: const Text(AppStrings.rejectReferral),
                ),
              ],
              if (r.status == ReferralStatuses.inProgress)
                OutlinedButton(
                  key: const Key('referral-complete'),
                  onPressed: () => act('complete'),
                  child: const Text(AppStrings.completeReferral),
                ),
              if (r.patientId != null)
                OutlinedButton.icon(
                  key: const Key('referral-open-patient'),
                  icon: const Icon(Icons.folder_shared_outlined),
                  label: const Text(AppStrings.openPatientFile),
                  onPressed: () => context.go(AppRoutes.patientDetail(r.patientId!)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ReferralView(referral: r, showDoctor: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

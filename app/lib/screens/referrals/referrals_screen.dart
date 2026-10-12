import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/doctors_repository.dart';
import '../../models/doctors.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import '../doctor/doctor_providers.dart';
import '../doctor/links_panel.dart';

/// Lab side of doctor linking (plan `doctor_linking`): referral inbox + linked doctors.
class ReferralsScreen extends ConsumerWidget {
  const ReferralsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: AppStrings.referralsTitle),
          TabBar(
            tabs: [
              Tab(key: Key('tab-inbox'), text: AppStrings.referralInbox),
              Tab(key: Key('tab-doctors'), text: AppStrings.linkedDoctors),
            ],
          ),
          SizedBox(height: 12),
          Expanded(child: TabBarView(children: [_Inbox(), _Doctors()])),
        ],
      ),
    );
  }
}

class _Inbox extends ConsumerStatefulWidget {
  const _Inbox();

  @override
  ConsumerState<_Inbox> createState() => _InboxState();
}

class _InboxState extends ConsumerState<_Inbox> {
  ReferralQuery _q = (search: '', status: ReferralStatuses.open.join(','));
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '${AppStrings.patientName} / ${AppStrings.doctor}',
                  ),
                  onChanged: (text) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 300),
                      () => setState(() => _q = (search: text, status: _q.status)),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  key: const Key('referrals-status'),
                  isExpanded: true,
                  initialValue: _q.status,
                  decoration: const InputDecoration(labelText: AppStrings.status),
                  items: [
                    DropdownMenuItem<String?>(
                      value: ReferralStatuses.open.join(','),
                      child: const Text(AppStrings.openReferralsOnly),
                    ),
                    const DropdownMenuItem<String?>(value: null, child: Text(AppStrings.all)),
                    for (final s in AppStrings.referralStatuses.entries)
                      DropdownMenuItem<String?>(value: s.key, child: Text(s.value)),
                  ],
                  onChanged: (v) => setState(() => _q = (search: _q.search, status: v)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncView(
            value: ref.watch(referralInboxProvider(_q)),
            onRetry: () => ref.invalidate(referralInboxProvider(_q)),
            builder: (refs) => refs.isEmpty
                ? const Center(child: Text(AppStrings.noReferrals))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [
                      for (final r in refs)
                        Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            key: Key('referral-row-${r.id}'),
                            leading: Icon(
                              r.isOpen ? Icons.mark_email_unread_outlined : Icons.drafts_outlined,
                            ),
                            title: Text('${r.patientName} — ${r.doctorName}'),
                            subtitle: Text(
                              [
                                Formatters.dateTime(r.createdAt),
                                if (r.diagnosis.isNotEmpty) r.diagnosis,
                              ].join('   •   '),
                            ),
                            trailing: Text(
                              AppStrings.label(AppStrings.referralStatuses, r.status),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onTap: () => context.go(AppRoutes.referralDetail(r.id)),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Doctors extends ConsumerWidget {
  const _Doctors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(sessionProvider)?.isOwner ?? false;
    final repo = ref.read(referralsRepositoryProvider);
    final code = isOwner ? ref.watch(labLinkCodeProvider).value : null;

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        invalidateReferrals(ref);
      } catch (e) {
        if (context.mounted) showErrorSnack(context, e);
      }
    }

    return AsyncView(
      value: ref.watch(labDoctorLinksProvider),
      onRetry: () => ref.invalidate(labDoctorLinksProvider),
      builder: (links) => LinksPanel(
        side: 'lab',
        links: links,
        code: code,
        canManage: isOwner,
        onRegenerate: () => run(() async {
          await repo.labCode(regenerate: true);
          ref.invalidate(labLinkCodeProvider);
        }),
        onRequest: (c) => run(() => repo.requestLink(c)),
        onAction: (link, action) => run(() => repo.linkAction(link.id, action)),
      ),
    );
  }
}

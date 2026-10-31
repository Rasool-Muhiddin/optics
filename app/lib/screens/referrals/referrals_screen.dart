import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
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
          PageHeader(
            title: AppStrings.referralsTitle,
            cacheTables: [CacheTables.referrals, CacheTables.labDoctorLinks],
          ),
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
        FilterBar(
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
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.page,
            ),
            child: AsyncView(
              value: ref.watch(referralInboxProvider(_q)),
              skeleton: true,
              onRetry: () => ref.invalidate(referralInboxProvider(_q)),
              builder: (refs) => refs.isEmpty
                  ? const EmptyState(
                      icon: Icons.medical_services_outlined,
                      title: AppStrings.noReferrals,
                    )
                  : AppDataTable<Referral>(
                      columns: const [
                        TableCol(AppStrings.patientName, flex: 3),
                        TableCol(AppStrings.doctor, flex: 3),
                        TableCol(AppStrings.diagnosis, flex: 3),
                        TableCol(AppStrings.date, flex: 2),
                        TableCol(AppStrings.status, flex: 2, center: true),
                      ],
                      items: refs,
                      rowKey: (r) => Key('referral-row-${r.id}'),
                      onTap: (r) => context.go(AppRoutes.referralDetail(r.id)),
                      accent: (r) => r.isOpen ? Theme.of(context).colorScheme.primary : null,
                      sortKeys: {
                        0: (r) => r.patientName,
                        1: (r) => r.doctorName,
                        3: (r) => r.createdAt?.millisecondsSinceEpoch ?? 0,
                      },
                      footer: TableFooter(count: refs.length),
                      cells: (r) => [
                        Row(
                          children: [
                            Icon(
                              r.isOpen ? Icons.mark_email_unread_outlined : Icons.drafts_outlined,
                              size: 18,
                              color: r.isOpen
                                  ? Theme.of(context).colorScheme.primary
                                  : AppColors.of(context).textMuted,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                              child: Text(
                                r.patientName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: r.isOpen ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(r.doctorName, overflow: TextOverflow.ellipsis),
                        Text(
                          r.diagnosis.isEmpty ? AppStrings.none : r.diagnosis,
                          overflow: TextOverflow.ellipsis,
                        ),
                        NumText(Formatters.dateTime(r.createdAt)),
                        StatusBadge(
                          label: AppStrings.label(AppStrings.referralStatuses, r.status),
                          tone: StatusTones.referral(r.status),
                          dense: true,
                        ),
                      ],
                    ),
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

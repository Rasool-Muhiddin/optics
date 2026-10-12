import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/doctors_repository.dart';
import '../../models/doctors.dart';

// Doctor side.
final doctorLinksProvider = FutureProvider.autoDispose<List<DoctorLink>>(
  (ref) => ref.watch(doctorRepositoryProvider).links(),
);

final doctorReferralsProvider = FutureProvider.autoDispose.family<List<Referral>, String?>(
  (ref, status) => ref.watch(doctorRepositoryProvider).referrals(status: status),
);

void invalidateDoctor(WidgetRef ref) {
  ref.invalidate(doctorLinksProvider);
  ref.invalidate(doctorReferralsProvider);
}

// Lab side.
final referralInboxProvider = FutureProvider.autoDispose.family<List<Referral>, ReferralQuery>(
  (ref, q) => ref.watch(referralsRepositoryProvider).inbox(q),
);

final labReferralProvider = FutureProvider.autoDispose.family<Referral, int>(
  (ref, id) => ref.watch(referralsRepositoryProvider).referral(id),
);

final labDoctorLinksProvider = FutureProvider.autoDispose<List<DoctorLink>>(
  (ref) => ref.watch(referralsRepositoryProvider).links(),
);

final labLinkCodeProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(referralsRepositoryProvider).labCode(),
);

void invalidateReferrals(WidgetRef ref, [int? id]) {
  if (id != null) ref.invalidate(labReferralProvider(id));
  ref.invalidate(referralInboxProvider);
  ref.invalidate(labDoctorLinksProvider);
}

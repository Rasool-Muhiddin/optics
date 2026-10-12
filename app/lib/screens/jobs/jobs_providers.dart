import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/jobs_repository.dart';
import '../../models/jobs.dart';

final jobBoardProvider = FutureProvider.autoDispose.family<List<Job>, JobQuery>(
  (ref, q) => ref.watch(jobsRepositoryProvider).board(q),
);

final jobProvider = FutureProvider.autoDispose.family<Job, int>(
  (ref, id) => ref.watch(jobsRepositoryProvider).get(id),
);

final patientJobsProvider = FutureProvider.autoDispose.family<List<Job>, int>(
  (ref, patientId) => ref.watch(jobsRepositoryProvider).ofPatient(patientId),
);

void invalidateJobs(WidgetRef ref, [int? jobId]) {
  if (jobId != null) ref.invalidate(jobProvider(jobId));
  ref.invalidate(jobBoardProvider);
  ref.invalidate(patientJobsProvider);
}

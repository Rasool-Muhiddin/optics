import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/patients_repository.dart';
import '../../models/json.dart';
import '../../models/patients.dart';

typedef PatientQuery = ({String search, String? status});

final patientListProvider = FutureProvider.autoDispose.family<PageResult<Patient>, PatientQuery>(
  (ref, q) => ref.watch(patientsRepositoryProvider).list(search: q.search, status: q.status),
);

final patientProvider = FutureProvider.autoDispose.family<Patient, int>(
  (ref, id) => ref.watch(patientsRepositoryProvider).get(id),
);

final patientExamsProvider = FutureProvider.autoDispose.family<List<EyeExam>, int>(
  (ref, id) => ref.watch(patientsRepositoryProvider).exams(id),
);

final patientPrescriptionsProvider = FutureProvider.autoDispose.family<List<Prescription>, int>(
  (ref, id) => ref.watch(patientsRepositoryProvider).prescriptions(id),
);

void invalidatePatient(WidgetRef ref, int id) {
  ref.invalidate(patientProvider(id));
  ref.invalidate(patientExamsProvider(id));
  ref.invalidate(patientPrescriptionsProvider(id));
  ref.invalidate(patientListProvider);
}

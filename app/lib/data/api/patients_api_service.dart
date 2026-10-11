import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// `patients/*` endpoints (patients, exams with nested Rx, standalone prescriptions).
class PatientsApiService {
  const PatientsApiService(this._client);

  final ApiClient _client;

  Future<dynamic> patients(Map<String, dynamic> query) => _client.get('patients/', query: query);

  Future<Map<String, dynamic>> patient(int id) async =>
      await _client.get('patients/$id/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> savePatient(int? id, Map<String, dynamic> body) async =>
      await (id == null
              ? _client.post('patients/', body: body)
              : _client.patch('patients/$id/', body: body))
          as Map<String, dynamic>;

  Future<dynamic> exams(int patientId) =>
      _client.get('patients/exams/', query: {'patient': patientId, 'page_size': 200});

  Future<Map<String, dynamic>> saveExam(int? id, Map<String, dynamic> body) async =>
      await (id == null
              ? _client.post('patients/exams/', body: body)
              : _client.patch('patients/exams/$id/', body: body))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> voidExam(int id, String reason) async =>
      await _client.post('patients/exams/$id/void/', body: {'reason': reason})
          as Map<String, dynamic>;

  Future<dynamic> prescriptions(int patientId) =>
      _client.get('patients/prescriptions/', query: {'patient': patientId, 'page_size': 200});

  Future<Map<String, dynamic>> savePrescription(int? id, Map<String, dynamic> body) async =>
      await (id == null
              ? _client.post('patients/prescriptions/', body: body)
              : _client.patch('patients/prescriptions/$id/', body: body))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> voidPrescription(int id, String reason) async =>
      await _client.post('patients/prescriptions/$id/void/', body: {'reason': reason})
          as Map<String, dynamic>;
}

final patientsApiServiceProvider = Provider<PatientsApiService>(
  (ref) => PatientsApiService(ref.watch(apiClientProvider)),
);

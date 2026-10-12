import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optics_app/app.dart';
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/data/api/api_client.dart';
import 'package:optics_app/data/cache/cache_database.dart';
import 'package:optics_app/models/patients.dart';
import 'package:optics_app/models/session.dart';
import 'package:optics_app/services/auth_storage.dart';
import 'package:optics_app/services/connectivity_service.dart';
import 'package:optics_app/services/printing/patient_pdfs.dart';
import 'package:optics_app/services/printing/pdf_kit.dart';
import 'package:optics_app/services/printing/print_service.dart';

import '../helpers.dart';

Map<String, dynamic> patientJson() => {
  'id': 5,
  'full_name': 'زينب علي',
  'birth_date': '1990-01-01',
  'birth_date_estimated': false,
  'age': 36,
  'gender': 'female',
  'phone': '07701234567',
  'address': 'بغداد',
  'notes': '',
  'status': 'exam_done',
  'is_archived': false,
  'last_exam_date': '2026-10-01',
};

Map<String, dynamic> rxJson() => {
  'id': 30,
  'patient': 5,
  'exam': 20,
  'rx_date': '2026-10-01',
  'od_sph': '-2.25',
  'od_cyl': '-0.50',
  'od_axis': 170,
  'od_add': null,
  'od_prism': null,
  'od_base': '',
  'od_va': '6/6',
  'os_sph': '-2.00',
  'os_cyl': '0.00',
  'os_axis': null,
  'os_add': null,
  'os_prism': null,
  'os_base': '',
  'os_va': '6/6',
  'pd_distance': '62.0',
  'usage': 'distance',
  'lens_design': 'single_vision',
  'lens_index': '1.60',
  'lens_coatings': ['ar', 'blue_cut'],
  'frame_notes': '',
  'notes': 'استخدام دائم',
  'is_void': false,
};

Map<String, dynamic> examJson() => {
  'id': 20,
  'patient': 5,
  'exam_date': '2026-10-01',
  'examined_by_name': 'owner1',
  'examiner_name': '',
  'chief_complaint': 'ضعف رؤية البعيد',
  'diagnosis': 'Myopia',
  'diagnosis_details': '',
  'va_od': '6/18',
  'va_os': '6/12',
  'iop_od': '15.0',
  'iop_os': null,
  'notes': '',
  'prescription': rxJson(),
  'is_void': false,
};

FakeAuthServer patientsServer() {
  final server = loggedInServer();
  server.routes.addAll({
    'GET patients/': (_) async => jsonResponse(page([patientJson()]), 200),
    'GET patients/5/': (_) async => jsonResponse(patientJson(), 200),
    'GET patients/exams/': (_) async => jsonResponse(page([examJson()]), 200),
    'GET patients/prescriptions/': (_) async => jsonResponse(page([rxJson()]), 200),
    'POST patients/exams/': (http.Request r) async {
      final body = decodeBody(r);
      if ((body['prescription'] as Map)['od_sph'] == '-2.00') {
        return jsonResponse({
          'detail': 'Validation failed.',
          'code': 'validation_error',
          'errors': {
            'prescription': {
              'od_axis': ['AXIS is required'],
            },
          },
          'error_codes': {
            'prescription': {
              'od_axis': ['axis_required'],
            },
          },
        }, 400);
      }
      return jsonResponse(examJson(), 201);
    },
  });
  return server;
}

Future<List<(String, Uint8List)>> pumpPatients(WidgetTester tester, FakeAuthServer server) async {
  final printed = <(String, Uint8List)>[];
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = await loggedInStorage();
  final cache = await openTestCache();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(storage),
        httpClientProvider.overrideWithValue(MockClient(server.handle)),
        connectivityServiceProvider.overrideWithValue(fakeConnectivity(serverUp: true)),
        cacheDatabaseProvider.overrideWithValue(cache),
        printServiceProvider.overrideWithValue(
          PrintService(
            lab: const LabInfo(id: 7, name: 'مختبر النور'),
            logoLoader: (_) async => null,
            printer: (bytes, name, format) async => printed.add((name, bytes)),
          ),
        ),
      ],
      child: const OpticsApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-/patients')));
  await tester.pumpAndSettle();
  return printed;
}

void main() {
  testWidgets('patient list opens the profile with exam history and Rx summary', (tester) async {
    await pumpPatients(tester, patientsServer());
    expect(find.text('زينب علي'), findsOneWidget);
    await tester.tap(find.byKey(const Key('patient-row-5')));
    await tester.pumpAndSettle();

    expect(find.text('${AppStrings.diagnosis}: Myopia'), findsOneWidget);
    expect(find.text('OD -2.25 -0.50×170 | OS -2.00'), findsOneWidget);
  });

  testWidgets('new exam sends the nested Rx and shows server field errors', (tester) async {
    final server = patientsServer();
    await pumpPatients(tester, server);
    await tester.tap(find.byKey(const Key('patient-row-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-exam')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('exam-diagnosis')), 'Myopia');
    // Local validation first: cylinder without axis.
    await tester.enterText(find.byKey(const Key('rx-od_sph')), '-2');
    await tester.enterText(find.byKey(const Key('rx-od_cyl')), '-0.5');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.axisRequired), findsOneWidget);
    expect(server.sent('POST', 'patients/exams/'), isEmpty);

    // Server-side error code mapped back onto the field.
    await tester.enterText(find.byKey(const Key('rx-od_axis')), '90');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();
    final body = decodeBody(server.sent('POST', 'patients/exams/').single);
    expect(body['patient'], 5);
    expect(body['diagnosis'], 'Myopia');
    expect((body['prescription'] as Map)['od_axis'], 90);
    expect(find.text(AppStrings.errAxisRequired), findsWidgets);
  });

  testWidgets('printing an exam report produces a PDF', (tester) async {
    final printed = await pumpPatients(tester, patientsServer());
    await tester.tap(find.byKey(const Key('patient-row-5')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('print-report-20')));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    expect(printed, hasLength(1));
    expect(printed.single.$1, AppStrings.examReportTitle);
    expect(String.fromCharCodes(printed.single.$2.take(4)), '%PDF');
  });

  test('prescription and exam report PDFs build with Arabic + Latin text', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final kit = await PdfKit.load(
      const LabInfo(id: 1, name: 'مختبر النور', phone: '0770', printFooter: 'شكراً لزيارتكم'),
    );
    final pdfs = PatientPdfs(kit);
    final patient = Patient.fromJson(patientJson());
    final rx = await pdfs.prescription(patient: patient, rx: Prescription.fromJson(rxJson()));
    final report = await pdfs.examReport(patient: patient, exam: EyeExam.fromJson(examJson()));
    expect(String.fromCharCodes(rx.take(4)), '%PDF');
    expect(report.length, greaterThan(rx.length ~/ 2));
  });
}

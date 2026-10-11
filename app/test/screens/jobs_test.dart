import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/models/jobs.dart';
import 'package:optics_app/models/session.dart';
import 'package:optics_app/services/printing/job_ticket_pdf.dart';
import 'package:optics_app/services/printing/pdf_kit.dart';

import '../helpers.dart';
import 'patients_test.dart' show patientJson, rxJson;

String _day(int offset) =>
    DateTime.now().add(Duration(days: offset)).toIso8601String().substring(0, 10);

Map<String, dynamic> jobJson({
  int id = 1,
  int number = 1,
  String status = 'pending',
  int promisedIn = 2,
  bool overdue = false,
  String frameSource = 'lab',
}) => {
  'id': id,
  'number': number,
  'patient': 5,
  'patient_name': 'زينب علي',
  'patient_phone': '0770',
  'prescription': 30,
  'prescription_detail': rxJson(),
  'invoice': null,
  'invoice_number': null,
  'invoice_balance': null,
  'frame_source': frameSource,
  'frame': null,
  'frame_name': frameSource == 'lab' ? 'Ray-Ban 5154' : '',
  'frame_notes': '',
  'lens': 2,
  'lens_name': 'CR-39 1.56',
  'lens_od': 12,
  'lens_od_label': 'SPH -1.00 CYL +0.00',
  'lens_os': null,
  'lens_os_label': '',
  'lens_notes': '',
  'status': status,
  'promised_date': _day(promisedIn),
  'is_overdue': overdue,
  'delivered_at': null,
  'notes': '',
  'status_logs': [
    {'from_status': '', 'to_status': 'pending', 'note': '', 'changed_by_name': 'owner1'},
  ],
  'created_at': '2026-10-10T09:00:00Z',
};

FakeAuthServer jobsServer() {
  final server = loggedInServer();
  server.routes.addAll({
    'GET jobs/': (http.Request r) async {
      final status = r.url.queryParameters['status'] ?? '';
      if (status == 'delivered') return jsonResponse(page([]), 200);
      return jsonResponse(
        page([
          jobJson(id: 1, number: 7, promisedIn: -2, overdue: true),
          jobJson(id: 2, number: 8, status: 'in_workshop'),
          jobJson(id: 3, number: 9, status: 'ready', promisedIn: -5),
        ]),
        200,
      );
    },
    'POST jobs/2/status/': (http.Request r) async =>
        jsonResponse(jobJson(id: 2, number: 8, status: decodeBody(r)['status'] as String), 200),
    'GET patients/': (_) async => jsonResponse(page([patientJson()]), 200),
    'GET patients/prescriptions/': (_) async => jsonResponse(page([rxJson()]), 200),
    'GET sales/invoices/': (_) async => jsonResponse(page([]), 200),
    'POST jobs/': (http.Request r) async =>
        jsonResponse({...jobJson(id: 4, number: 10), ...decodeBody(r)}, 201),
    'GET jobs/4/': (_) async =>
        jsonResponse(jobJson(id: 4, number: 10, frameSource: 'customer'), 200),
  });
  return server;
}

Future<void> openJobs(WidgetTester tester, FakeAuthServer server) async {
  tester.view.physicalSize = const Size(1800, 1100);
  await pumpOpticsApp(tester, server: server, storage: await loggedInStorage());
  tester.view.physicalSize = const Size(1800, 1100);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-/jobs')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('board groups jobs by status and flags overdue ones', (tester) async {
    await openJobs(tester, jobsServer());

    expect(
      find.descendant(
        of: find.byKey(const Key('job-column-pending')),
        matching: find.byKey(const Key('job-card-1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('job-column-in_workshop')),
        matching: find.byKey(const Key('job-card-2')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('job-overdue-1')), findsOneWidget);
    // Ready jobs are waiting for the customer, not late work.
    expect(find.byKey(const Key('job-overdue-3')), findsNothing);
  });

  testWidgets('"move to" posts the next status', (tester) async {
    final server = jobsServer();
    await openJobs(tester, server);
    await tester.tap(find.byKey(const Key('job-next-2')));
    await tester.pumpAndSettle();
    expect(decodeBody(server.sent('POST', 'jobs/2/status/').single), {
      'status': 'ready',
      'note': '',
    });
  });

  testWidgets("new job with the customer's own frame", (tester) async {
    final server = jobsServer();
    await openJobs(tester, server);
    await tester.tap(find.byKey(const Key('new-job')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('job-pick-patient')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-patient-5')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.frameSources['customer']!));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('job-frame-notes')), 'إطار معدني أسود');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    final body = decodeBody(server.sent('POST', 'jobs/').single);
    expect(body['patient'], 5);
    expect(body['frame_source'], 'customer');
    expect(body['frame'], isNull);
    expect(body['frame_notes'], 'إطار معدني أسود');
    expect(body['promised_date'], isNotNull);
  });

  test('overdue is re-evaluated offline for active statuses only', () {
    final today = DateTime.now();
    expect(Job.fromJson(jobJson(promisedIn: -1)).overdueOn(today), isTrue);
    expect(Job.fromJson(jobJson(promisedIn: 0)).overdueOn(today), isFalse);
    expect(Job.fromJson(jobJson(promisedIn: -1, status: 'ready')).overdueOn(today), isFalse);
    expect(Job.fromJson(jobJson(promisedIn: -1, status: 'delivered')).overdueOn(today), isFalse);
  });

  test('job ticket PDF builds in A5 and 80mm', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final kit = await PdfKit.load(const LabInfo(id: 1, name: 'مختبر النور'));
    final job = Job.fromJson(jobJson(frameSource: 'customer'));
    for (final thermal in [false, true]) {
      final bytes = await JobTicketPdf(kit).build(job, thermal: thermal);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });
}

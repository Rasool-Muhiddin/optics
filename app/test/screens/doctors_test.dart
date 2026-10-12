import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optics_app/core/router/app_router.dart';
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/models/doctors.dart';
import 'package:optics_app/services/auth_controller.dart';
import 'package:optics_app/services/auth_storage.dart';

import '../helpers.dart';

Map<String, dynamic> doctorSessionJson() => {
  'role': 'doctor',
  'user': {'id': 9, 'username': 'doc1', 'first_name': '', 'last_name': '', 'email': ''},
  'doctor': {
    'id': 3,
    'full_name': 'د. سامر',
    'specialty': 'Ophthalmology',
    'clinic_name': 'عيادة النور',
    'phone': '',
    'address': '',
    'link_code': 'DOC12345',
  },
};

Map<String, dynamic> referralJson({int id = 1, String status = 'sent', bool labSide = false}) => {
  'id': id,
  'lab': 7,
  'lab_name': 'مختبر النور',
  'status': status,
  'patient_name': 'زينب علي',
  'patient_age': 35,
  'patient_gender': 'female',
  'patient_phone': '0770',
  'exam_date': '2026-10-10',
  'chief_complaint': '',
  'diagnosis': 'Myopia',
  'diagnosis_details': '',
  'va_od': '6/12',
  'va_os': '6/9',
  'iop_od': null,
  'iop_os': null,
  'prescription': {'od_sph': '-2.50', 'od_cyl': '0.50', 'od_axis': 80, 'os_sph': '-2.00'},
  'notes': 'progressive',
  'reject_reason': '',
  'created_at': '2026-10-10T09:00:00Z',
  if (labSide) ...{
    'doctor': 3,
    'doctor_name': 'د. سامر',
    'doctor_clinic': 'عيادة النور',
    'doctor_phone': '',
    'patient': status == 'in_progress' ? 55 : null,
    'patient_file_name': '',
    'exam': null,
    'handled_by_name': '',
  },
};

Map<String, dynamic> linkJson({int id = 1, String status = 'accepted', String by = 'doctor'}) => {
  'id': id,
  'lab': 7,
  'lab_name': 'مختبر النور',
  'lab_phone': '0770',
  'lab_address': 'بغداد',
  'status': status,
  'requested_by': by,
  'requested_at': '2026-10-01T09:00:00Z',
  'responded_at': null,
  'note': '',
};

void addDoctorRoutes(FakeAuthServer server) {
  server.routes.addAll({
    'POST desktop/doctor-login/': (http.Request r) async {
      final body = decodeBody(r);
      if (body['password'] != 'pass') {
        return jsonResponse({'detail': 'x', 'code': 'invalid_credentials'}, 400);
      }
      server.tokens.add('doctor-token');
      return jsonResponse({'token': 'doctor-token', ...doctorSessionJson()}, 200);
    },
    'GET doctor/me/': (_) async => jsonResponse(doctorSessionJson(), 200),
    'GET doctor/referrals/': (_) async => jsonResponse(page([referralJson()]), 200),
    'POST doctor/referrals/': (http.Request r) async =>
        jsonResponse({...referralJson(id: 2), ...decodeBody(r)}, 201),
    'GET doctor/links/': (_) async =>
        jsonResponse(page([linkJson(), linkJson(id: 2, status: 'pending', by: 'lab')]), 200),
    'POST doctor/links/': (_) async => jsonResponse(linkJson(id: 3, status: 'pending'), 201),
    'POST doctor/links/2/accept/': (_) async => jsonResponse(linkJson(id: 2), 200),
  });
}

Future<AuthStorage> doctorStorage() => AuthStorage.open(
  MemoryAuthStore({'device_id': 'dev-1', 'token': 'doctor-token', 'session': doctorSessionJson()}),
);

Future<void> setSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1100);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('doctor logs in from the activation screen into doctor mode', (tester) async {
    final server = FakeAuthServer();
    addDoctorRoutes(server);
    final storage = await AuthStorage.open(MemoryAuthStore());
    await pumpOpticsApp(tester, server: server, storage: storage);
    await setSize(tester);

    await tester.tap(find.byKey(const Key('go-doctor-login')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('doctor-username')), 'doc1');
    await tester.enterText(find.byKey(const Key('doctor-password')), 'pass');
    await tester.tap(find.byKey(const Key('doctor-login-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('doctor-sidebar-name')), findsOneWidget);
    expect(find.byKey(const Key('doctor-referral-1')), findsOneWidget);
    // No lab sections in doctor mode.
    expect(find.byKey(const Key('nav-/pos')), findsNothing);
    expect(find.byKey(const Key('nav-/inventory')), findsNothing);
    expect(storage.isDoctorSession, isTrue);
    expect(storage.isActivated, isFalse);
  });

  testWidgets('doctor sends a referral with the Rx exactly as entered', (tester) async {
    final server = loggedInServer();
    addDoctorRoutes(server);
    server.tokens.add('doctor-token');
    await pumpOpticsApp(tester, server: server, storage: await doctorStorage());
    await setSize(tester);

    await tester.tap(find.byKey(const Key('new-referral')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('referral-lab')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مختبر النور').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('referral-patient-name')), 'زينب علي');
    await tester.enterText(find.byKey(const Key('rx-od_sph')), '-2.50');
    await tester.enterText(find.byKey(const Key('rx-od_cyl')), '+0.50');
    await tester.enterText(find.byKey(const Key('rx-od_axis')), '80');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    final body = decodeBody(server.sent('POST', 'doctor/referrals/').single);
    expect(body['lab'], 7);
    expect(body['patient_name'], 'زينب علي');
    final rx = body['prescription'] as Map<String, dynamic>;
    expect((rx['od_sph'], rx['od_cyl'], rx['od_axis']), ('-2.50', '0.50', 80));
    expect(find.text(AppStrings.referralSent), findsOneWidget);
  });

  testWidgets('doctor labs: own code, request by lab code, accept a lab request', (tester) async {
    final server = loggedInServer();
    addDoctorRoutes(server);
    server.tokens.add('doctor-token');
    await pumpOpticsApp(tester, server: server, storage: await doctorStorage());
    await setSize(tester);
    await tester.tap(find.byKey(const Key('nav-/doctor/labs')));
    await tester.pumpAndSettle();

    expect(find.text('DOC12345'), findsOneWidget);
    // The doctor cannot answer their own request; a lab request can be accepted.
    expect(find.byKey(const Key('link-accept-1')), findsNothing);
    await tester.tap(find.byKey(const Key('link-accept-2')));
    await tester.pumpAndSettle();
    expect(server.sent('POST', 'doctor/links/2/accept/'), hasLength(1));

    await tester.enterText(find.byKey(const Key('link-code-input')), 'lab9 code');
    await tester.tap(find.byKey(const Key('link-request')));
    await tester.pumpAndSettle();
    expect(decodeBody(server.sent('POST', 'doctor/links/').single), {'code': 'lab9 code'});
  });

  testWidgets('lab inbox: accept a referral into a new patient file', (tester) async {
    final server = loggedInServer(session: sessionJson(doctorLinking: true));
    server.routes.addAll({
      'GET referrals/': (_) async => jsonResponse(page([referralJson(labSide: true)]), 200),
      'GET referrals/1/': (_) async => jsonResponse(referralJson(labSide: true), 200),
      'POST referrals/1/accept/': (_) async =>
          jsonResponse(referralJson(labSide: true, status: 'in_progress'), 200),
      'GET referrals/links/': (_) async => jsonResponse(page([]), 200),
      'GET referrals/links/code/': (_) async => jsonResponse({'code': 'LAB98765'}, 200),
    });
    await pumpOpticsApp(
      tester,
      server: server,
      storage: await loggedInStorage(session: server.session),
    );
    await setSize(tester);
    await tester.tap(find.byKey(const Key('nav-/referrals')));
    await tester.pumpAndSettle();
    expect(server.sent('GET', 'referrals/').first.url.queryParameters['status'], 'sent,received');

    await tester.tap(find.byKey(const Key('referral-row-1')));
    await tester.pumpAndSettle();
    expect(find.text('+0.50'), findsOneWidget); // Rx shown as entered
    await tester.tap(find.byKey(const Key('referral-accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept-new-patient')));
    await tester.pumpAndSettle();
    expect(decodeBody(server.sent('POST', 'referrals/1/accept/').single), isEmpty);

    await tester.tap(find.byKey(const Key('nav-/referrals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-doctors')));
    await tester.pumpAndSettle();
    expect(find.text('LAB98765'), findsOneWidget);
  });

  testWidgets('referrals section is hidden without the plan feature', (tester) async {
    await pumpOpticsApp(tester, server: loggedInServer(), storage: await loggedInStorage());
    expect(find.byKey(const Key('nav-/referrals')), findsNothing);
  });

  test('doctor mode is confined to /doctor routes and labs to theirs', () {
    final doctor = DoctorLoggedIn(DoctorSession.fromJson(doctorSessionJson()));
    expect(authRedirect(doctor, '/pos'), AppRoutes.doctorHome);
    expect(authRedirect(doctor, '/doctor/labs'), isNull);
    expect(authRedirect(const NeedsActivation(), AppRoutes.doctorLogin), isNull);
    expect(authRedirect(const LoggedOut(labName: ''), AppRoutes.doctorLogin), isNull);
  });
}

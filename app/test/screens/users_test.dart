import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optics_app/core/strings/app_strings.dart';

import '../helpers.dart';

Map<String, dynamic> userJson({
  int id = 2,
  String username = 'cash1',
  String role = 'staff',
  bool active = true,
  bool costs = false,
  bool inventory = false,
}) => {
  'id': id,
  'user_id': id + 10,
  'username': username,
  'first_name': 'علي',
  'last_name': '',
  'phone': '0770',
  'role': role,
  'can_view_costs': costs,
  'can_manage_inventory': inventory,
  'is_active': active,
  'last_login': null,
  'created_at': '2026-10-01T09:00:00Z',
};

FakeAuthServer usersServer({int users = 2, int maxUsers = 3}) {
  final server = loggedInServer();
  server.routes.addAll({
    'GET lab/users/': (_) async =>
        jsonResponse(page([userJson(id: 1, username: 'owner1', role: 'owner'), userJson()]), 200),
    'GET lab/devices/': (_) async => jsonResponse(
      page([
        {'id': 3, 'device_id': 'dev-1', 'name': 'PC', 'is_active': true, 'app_version': '0.1.0'},
        {'id': 4, 'device_id': 'dev-2', 'name': 'Front desk', 'is_active': true, 'app_version': ''},
      ]),
      200,
    ),
    'GET lab/usage/': (_) async =>
        jsonResponse({'users': users, 'max_users': maxUsers, 'devices': 2, 'max_devices': 2}, 200),
    'POST lab/users/': (http.Request r) async =>
        jsonResponse({...userJson(id: 9), ...decodeBody(r)}, 201),
    'PATCH lab/users/2/': (http.Request r) async =>
        jsonResponse({...userJson(), ...decodeBody(r)}, 200),
    'PATCH lab/devices/4/': (http.Request r) async => jsonResponse({
      'id': 4,
      'device_id': 'dev-2',
      'name': 'Front desk',
      'is_active': false,
    }, 200),
  });
  return server;
}

Future<void> openUsers(WidgetTester tester, FakeAuthServer server) async {
  await pumpOpticsApp(tester, server: server, storage: await loggedInStorage());
  await tester.tap(find.byKey(const Key('nav-/users')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists users with plan usage and adds a staff member', (tester) async {
    final server = usersServer();
    await openUsers(tester, server);

    expect(find.byKey(const Key('user-row-2')), findsOneWidget);
    expect(find.textContaining('${AppStrings.usersUsage}: 2 / 3'), findsOneWidget);
    expect(find.textContaining('${AppStrings.devicesUsage}: 2 / 2'), findsOneWidget);
    expect(find.text(AppStrings.limitReachedDevices), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('user-username')), 'sara');
    await tester.enterText(find.byKey(const Key('user-first-name')), 'سارة');
    await tester.enterText(find.byKey(const Key('user-phone')), '0780');
    await tester.enterText(find.byKey(const Key('user-password')), 'short');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.passwordMin), findsOneWidget);
    await tester.enterText(find.byKey(const Key('user-password')), 'Sara-Pass-123');
    await tester.tap(find.byKey(const Key('user-can-manage-inventory')));
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    final body = decodeBody(server.sent('POST', 'lab/users/').single);
    expect(body['username'], 'sara');
    expect(body['phone'], '0780');
    expect(body['role'], 'staff');
    expect(body['can_manage_inventory'], isTrue);
    expect(body['can_view_costs'], isFalse);
  });

  testWidgets('user limit reached: adding shows the Arabic message', (tester) async {
    final server = usersServer(users: 3, maxUsers: 3);
    await openUsers(tester, server);
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.limitReachedUsers), findsWidgets);
    expect(server.sent('POST', 'lab/users/'), isEmpty);
  });

  testWidgets('server limit error is shown in Arabic', (tester) async {
    final server = usersServer();
    server.routes['POST lab/users/'] = (_) async =>
        jsonResponse({'detail': 'x', 'code': 'user_limit_reached'}, 400);
    await openUsers(tester, server);
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('user-username')), 'x');
    await tester.enterText(find.byKey(const Key('user-password')), 'Long-Pass-123');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.errUserLimit), findsOneWidget);
  });

  testWidgets('edit resets password, toggles costs and deactivates', (tester) async {
    final server = usersServer();
    await openUsers(tester, server);
    await tester.tap(find.byKey(const Key('edit-user-2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('user-password')), 'N3w-Passw0rd!');
    await tester.tap(find.byKey(const Key('user-can-view-costs')));
    await tester.tap(find.byKey(const Key('user-active')));
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();

    final body = decodeBody(server.sent('PATCH', 'lab/users/2/').single);
    expect(body['password'], 'N3w-Passw0rd!');
    expect(body['can_view_costs'], isTrue);
    expect(body['is_active'], isFalse);
    expect(body.containsKey('username'), isFalse);
  });

  testWidgets('revoke another device; this device cannot be revoked', (tester) async {
    final server = usersServer();
    await openUsers(tester, server);
    await tester.tap(find.byKey(const Key('tab-devices')));
    await tester.pumpAndSettle();

    expect(find.textContaining(AppStrings.thisDevice), findsOneWidget);
    expect(find.byKey(const Key('revoke-device-3')), findsNothing);
    await tester.tap(find.byKey(const Key('revoke-device-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(decodeBody(server.sent('PATCH', 'lab/devices/4/').single), {'is_active': false});
  });

  testWidgets('users section is owner-only', (tester) async {
    final server = loggedInServer(session: sessionJson(role: 'staff'));
    await pumpOpticsApp(
      tester,
      server: server,
      storage: await loggedInStorage(session: server.session),
    );
    expect(find.byKey(const Key('nav-/users')), findsNothing);
  });
}

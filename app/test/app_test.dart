import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/core/errors/app_exception.dart';
import 'package:optics_app/data/api/auth_api_service.dart';
import 'package:optics_app/core/router/app_routes.dart';
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/services/auth_storage.dart';

import 'helpers.dart';

Future<AuthStorage> _storage([Map<String, dynamic>? data]) =>
    AuthStorage.open(MemoryAuthStore(data));

/// Storage of an activated device (optionally logged in with [token]).
Future<AuthStorage> _activated({String? token, Map<String, dynamic>? session}) => _storage({
  'device_id': 'dev-1',
  'device_key': 'device-key-1',
  'lab_id': 7,
  'lab_name': 'مختبر النور',
  'token': ?token,
  'session': ?session,
});

Future<void> _login(WidgetTester tester, {String password = 'pass'}) async {
  await tester.enterText(find.byKey(const Key('login-username')), 'owner1');
  await tester.enterText(find.byKey(const Key('login-password')), password);
  await tester.tap(find.byKey(const Key('login-button')));
  await tester.pumpAndSettle();
}

void main() {
  group('activation', () {
    testWidgets('fresh install opens the activation screen in RTL', (tester) async {
      await pumpOpticsApp(tester, server: FakeAuthServer(), storage: await _storage());

      expect(find.text(AppStrings.activationTitle), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(AppStrings.activationTitle))),
        TextDirection.rtl,
      );
    });

    testWidgets('empty or wrong code shows an Arabic error', (tester) async {
      await pumpOpticsApp(tester, server: FakeAuthServer(), storage: await _storage());

      await tester.tap(find.byKey(const Key('activate-button')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.activationCodeRequired), findsOneWidget);

      await tester.enterText(find.byKey(const Key('activation-code')), 'WRONG');
      await tester.tap(find.byKey(const Key('activate-button')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.errInvalidActivationCode), findsOneWidget);
    });

    testWidgets('valid code stores the device key and moves to login', (tester) async {
      final storage = await _storage();
      final server = FakeAuthServer();
      await pumpOpticsApp(tester, server: server, storage: storage);

      await tester.enterText(find.byKey(const Key('activation-code')), ' ABC123 ');
      await tester.tap(find.byKey(const Key('activate-button')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.loginTitle), findsOneWidget);
      expect(find.text('مختبر النور'), findsOneWidget);
      expect(storage.deviceKey, 'device-key-1');
      expect(storage.deviceId, isNotNull);
      final sent = server.requests.lastWhere((r) => r.url.path.endsWith('activate/'));
      expect(sent.body, contains('"device_id":"${storage.deviceId}"'));
    });
  });

  group('login', () {
    testWidgets('wrong password shows an error; right one opens the main layout', (tester) async {
      final storage = await _activated();
      await pumpOpticsApp(tester, server: FakeAuthServer(), storage: storage);

      await _login(tester, password: 'nope');
      expect(find.text(AppStrings.errInvalidCredentials), findsOneWidget);

      await _login(tester);
      expect(find.byKey(const Key('sidebar-lab-name')), findsOneWidget);
      expect(find.textContaining(AppStrings.welcome), findsOneWidget);
      expect(find.text(AppStrings.roleOwner), findsWidgets);
      expect(storage.token, 'token-1');
    });

    testWidgets('owner sees owner-only sections; feature-gated ones follow the plan', (
      tester,
    ) async {
      await pumpOpticsApp(tester, server: FakeAuthServer(), storage: await _activated());
      await _login(tester);

      expect(find.byKey(const Key('nav-${AppRoutes.users}')), findsOneWidget);
      expect(find.byKey(const Key('nav-${AppRoutes.reports}')), findsOneWidget);
      expect(find.byKey(const Key('nav-${AppRoutes.referrals}')), findsNothing);
    });

    testWidgets('staff does not see owner-only sections', (tester) async {
      final server = FakeAuthServer(session: sessionJson(role: 'staff', doctorLinking: true));
      await pumpOpticsApp(tester, server: server, storage: await _activated());
      await _login(tester);

      expect(find.byKey(const Key('nav-${AppRoutes.patients}')), findsOneWidget);
      expect(find.byKey(const Key('nav-${AppRoutes.referrals}')), findsOneWidget);
      expect(find.byKey(const Key('nav-${AppRoutes.users}')), findsNothing);
      expect(find.byKey(const Key('nav-${AppRoutes.settings}')), findsNothing);
      expect(find.text(AppStrings.roleStaff), findsWidgets);
    });

    testWidgets('login while offline is refused with the offline message', (tester) async {
      final connectivity = fakeConnectivity(serverUp: false);
      await pumpOpticsApp(
        tester,
        server: FakeAuthServer(),
        storage: await _activated(),
        connectivity: connectivity,
      );
      await tester.runAsync(connectivity.checkNow);

      await _login(tester);
      expect(find.text(AppStrings.errOfflineWrite), findsOneWidget);
      connectivity.dispose();
    });

    testWidgets('re-activate link returns to the activation screen', (tester) async {
      final storage = await _activated();
      await pumpOpticsApp(tester, server: FakeAuthServer(), storage: storage);

      await tester.tap(find.text(AppStrings.reactivate));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.activationTitle), findsOneWidget);
      expect(storage.deviceKey, isNull);
      expect(storage.deviceId, 'dev-1');
    });
  });

  group('stored session', () {
    testWidgets('valid token goes straight to the main layout', (tester) async {
      final server = FakeAuthServer()..tokens.add('saved');
      await pumpOpticsApp(
        tester,
        server: server,
        storage: await _activated(token: 'saved'),
      );

      expect(find.byKey(const Key('sidebar-lab-name')), findsOneWidget);
    });

    testWidgets('revoked token returns to login', (tester) async {
      final storage = await _activated(token: 'revoked', session: sessionJson());
      await pumpOpticsApp(tester, server: FakeAuthServer(), storage: storage);

      expect(find.text(AppStrings.loginTitle), findsOneWidget);
      expect(storage.token, isNull);
    });

    testWidgets('expired license logs out with an explanation', (tester) async {
      final server = FakeAuthServer()
        ..tokens.add('saved')
        ..meError = (status: 403, code: 'license_expired');
      await pumpOpticsApp(
        tester,
        server: server,
        storage: await _activated(token: 'saved'),
      );

      expect(find.text(AppStrings.loginTitle), findsOneWidget);
      expect(find.text(AppStrings.errLicenseExpired), findsOneWidget);
    });

    testWidgets('server unreachable: opens from the stored session (read-only)', (tester) async {
      final server = FakeAuthServer()..down = true;
      await pumpOpticsApp(
        tester,
        server: server,
        storage: await _activated(token: 'saved', session: sessionJson()),
      );

      expect(find.byKey(const Key('sidebar-lab-name')), findsOneWidget);
      expect(find.text(AppStrings.sessionOffline), findsOneWidget);
      expect(find.text(AppStrings.offline), findsOneWidget);
    });
  });

  group('main layout', () {
    testWidgets('sidebar navigates to a section', (tester) async {
      final server = FakeAuthServer()..tokens.add('saved');
      await pumpOpticsApp(
        tester,
        server: server,
        storage: await _activated(token: 'saved'),
      );

      await tester.tap(find.byKey(const Key('nav-${AppRoutes.users}')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.usersTitle), findsOneWidget);
    });

    testWidgets('logout revokes the token and returns to login', (tester) async {
      final server = FakeAuthServer()..tokens.add('saved');
      final storage = await _activated(token: 'saved');
      await pumpOpticsApp(tester, server: server, storage: storage);

      await tester.tap(find.byKey(const Key('logout-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.loginTitle), findsOneWidget);
      expect(server.tokens, isEmpty);
      expect(storage.token, isNull);
      expect(storage.deviceKey, 'device-key-1');
    });

    testWidgets('a 401 mid-session (token revoked) returns to login', (tester) async {
      final server = FakeAuthServer()..tokens.add('saved');
      final storage = await _activated(token: 'saved');
      await pumpOpticsApp(tester, server: server, storage: storage);

      server.tokens.clear();
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      await tester.runAsync(() async {
        await expectLater(
          container.read(authApiServiceProvider).me(),
          throwsA(isA<UnauthorizedException>()),
        );
      });
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.loginTitle), findsOneWidget);
      expect(find.text(AppStrings.errNotAuthenticated), findsOneWidget);
      expect(storage.token, isNull);
    });
  });
}

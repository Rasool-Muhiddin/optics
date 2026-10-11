import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/core/router/app_router.dart';
import 'package:optics_app/models/session.dart';
import 'package:optics_app/services/auth_controller.dart';

import '../helpers.dart';

void main() {
  final owner = LoggedIn(Session.fromJson(sessionJson()));
  final staff = LoggedIn(Session.fromJson(sessionJson(role: 'staff')));

  test('loading state waits on the splash screen', () {
    expect(authRedirect(null, AppRoutes.home), AppRoutes.splash);
    expect(authRedirect(null, AppRoutes.splash), isNull);
  });

  test('unactivated and logged-out users are kept on their screens', () {
    expect(authRedirect(const NeedsActivation(), AppRoutes.home), AppRoutes.activate);
    expect(authRedirect(const LoggedOut(labName: ''), AppRoutes.users), AppRoutes.login);
    expect(authRedirect(const LoggedOut(labName: ''), AppRoutes.login), isNull);
  });

  test('logged-in users leave public screens and cannot open hidden sections', () {
    expect(authRedirect(owner, AppRoutes.login), AppRoutes.home);
    expect(authRedirect(owner, AppRoutes.users), isNull);
    expect(authRedirect(staff, AppRoutes.users), AppRoutes.home);
    expect(authRedirect(staff, AppRoutes.patients), isNull);
    expect(authRedirect(owner, AppRoutes.referrals), AppRoutes.home);
  });
}

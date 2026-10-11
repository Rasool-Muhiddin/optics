import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/app.dart';
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/services/connectivity_service.dart';

import 'helpers.dart';

Future<void> _pumpApp(WidgetTester tester, ConnectivityService connectivity) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [connectivityServiceProvider.overrideWithValue(connectivity)],
      child: const OpticsApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('boots in RTL Arabic on the home screen', (tester) async {
    final connectivity = fakeConnectivity(serverUp: true);
    await _pumpApp(tester, connectivity);

    expect(find.text(AppStrings.appTitle), findsOneWidget);
    expect(find.text(AppStrings.welcome), findsOneWidget);
    expect(Directionality.of(tester.element(find.text(AppStrings.welcome))), TextDirection.rtl);
    expect(find.text(AppStrings.offline), findsNothing);
    connectivity.dispose();
  });

  testWidgets('shows the offline banner when the server is unreachable', (tester) async {
    final connectivity = fakeConnectivity(serverUp: false);
    await _pumpApp(tester, connectivity);

    await tester.runAsync(connectivity.checkNow);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.offline), findsOneWidget);
    connectivity.dispose();
  });
}

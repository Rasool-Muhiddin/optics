import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optics_app/core/errors/app_exception.dart';
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/services/update/update_service.dart';

import '../helpers.dart';

final _bytes = utf8.encode('MZ fake installer bytes');
final _sha = sha256.convert(_bytes).toString();

Map<String, dynamic> latestJson({bool mandatory = false, String? sha}) => {
  'available': true,
  'update_available': true,
  'mandatory': mandatory,
  'version': '1.1.0',
  'build_number': 3,
  'url': 'https://downloads.example.com/optics-1.1.0.exe',
  'sha256': sha ?? _sha,
  'size': _bytes.length,
  'release_notes': 'تحسينات',
};

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('upd'));
  tearDown(() => tmp.delete(recursive: true));

  UpdateService service({
    Map<String, dynamic>? latest,
    List<String>? started,
    List<bool>? exited,
    bool windows = true,
  }) => UpdateService(
    api: fakeApi((r) async {
      expect(r.url.queryParameters['version'], '1.0.0');
      return jsonResponse(latest ?? latestJson(), 200);
    }),
    httpClient: MockClient((r) async => http.Response.bytes(_bytes, 200)),
    currentVersion: '1.0.0',
    tempDir: () async => tmp,
    isWindows: windows,
    startProcess: (exe, args) async => started?.addAll([exe, ...args]),
    exitApp: () => exited?.add(true),
  );

  test('check returns the newer release; up to date returns null', () async {
    final info = await service().check();
    expect((info!.version, info.sha256, info.mandatory), ('1.1.0', _sha, false));
    final none = await service(latest: {'available': true, 'update_available': false}).check();
    expect(none, isNull);
  });

  test('download verifies SHA-256, then install starts the installer silently and exits', () async {
    final started = <String>[];
    final exited = <bool>[];
    final s = service(started: started, exited: exited);
    final progress = <double>[];
    final file = await s.download((await s.check())!, onProgress: progress.add);
    expect(await file.readAsBytes(), _bytes);
    expect(progress.last, 1.0);
    await s.install(file);
    expect(started.first, file.path);
    expect(started, containsAll(['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS']));
    expect(exited, [true]);
  });

  test('a tampered download is deleted and refused', () async {
    final s = service(latest: latestJson(sha: 'b' * 64));
    await expectLater(
      s.download((await s.check())!),
      throwsA(isA<UpdateException>().having((e) => e.code, 'code', 'update_checksum')),
    );
    expect(tmp.listSync(), isEmpty);
  });

  test('install is Windows only', () async {
    final s = service(windows: false);
    final file = await s.download((await s.check())!);
    expect(
      () => s.install(file),
      throwsA(isA<UpdateException>().having((e) => e.code, 'code', 'update_unsupported')),
    );
  });

  testWidgets('banner on the login screen; mandatory update is red', (tester) async {
    final server = FakeAuthServer();
    server.routes['GET desktop/latest-version/'] = (_) async =>
        jsonResponse(latestJson(mandatory: true), 200);
    await pumpOpticsApp(tester, server: server, storage: await loggedInStorage());
    // loggedInStorage has a token unknown to this server → login screen.
    expect(find.byKey(const Key('update-banner')), findsOneWidget);
    expect(find.textContaining(AppStrings.updateMandatory), findsOneWidget);
    await tester.tap(find.byKey(const Key('update-now')));
    await tester.pumpAndSettle();
    expect(find.text('تحسينات'), findsOneWidget);
  });
}

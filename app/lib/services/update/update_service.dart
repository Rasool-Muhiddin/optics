import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../data/api/api_client.dart';
import '../../models/json.dart';

/// `GET desktop/latest-version/` answer.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    required this.sha256,
    this.buildNumber = 0,
    this.size = 0,
    this.releaseNotes = '',
    this.mandatory = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
    version: Json.str(j['version']),
    buildNumber: Json.int0(j['build_number']),
    url: Json.str(j['url']),
    sha256: Json.str(j['sha256']).toLowerCase(),
    size: Json.int0(j['size']),
    releaseNotes: Json.str(j['release_notes']),
    mandatory: Json.boolean(j['mandatory']),
  );

  final String version;
  final int buildNumber;
  final String url;
  final String sha256;
  final int size;
  final String releaseNotes;
  final bool mandatory;
}

typedef ProcessStarter = Future<void> Function(String executable, List<String> arguments);

/// Desktop self-update: ask the server for the newest release, download the installer to
/// the temp folder, verify its SHA-256, start it silently and close the app (the Inno Setup
/// installer replaces the files and starts the new version from its `[Run]` section).
class UpdateService {
  UpdateService({
    required this.api,
    required this.httpClient,
    this.currentVersion = AppConfig.appVersion,
    ProcessStarter? startProcess,
    void Function()? exitApp,
    Future<Directory> Function()? tempDir,
    bool? isWindows,
  }) : _isWindows = isWindows ?? Platform.isWindows,
       _start = startProcess ?? _startDetached,
       _exit = exitApp ?? (() => exit(0)),
       _tempDir = tempDir ?? (() async => Directory.systemTemp);

  final ApiClient api;
  final http.Client httpClient;
  final String currentVersion;
  final ProcessStarter _start;
  final void Function() _exit;
  final Future<Directory> Function() _tempDir;
  final bool _isWindows;

  /// Arguments for the Inno Setup installer: no wizard pages, close and restart the app.
  static const installerArguments = [
    '/SILENT',
    '/SP-',
    '/NOCANCEL',
    '/CLOSEAPPLICATIONS',
    '/NORESTART',
  ];

  /// The newer release, or null when up to date (or nothing is published).
  Future<UpdateInfo?> check() async {
    final json =
        await api.get(
              'desktop/latest-version/',
              query: {'platform': 'windows', 'version': currentVersion},
            )
            as Map<String, dynamic>;
    if (json['update_available'] != true) return null;
    return UpdateInfo.fromJson(json);
  }

  /// Downloads the installer (progress 0..1) and checks its SHA-256. Returns the file.
  Future<File> download(UpdateInfo info, {void Function(double progress)? onProgress}) async {
    final dir = await _tempDir();
    final file = File(p.join(dir.path, 'optics-setup-${info.version}.exe'));
    final http.StreamedResponse response;
    try {
      response = await httpClient.send(
        http.Request('GET', Uri.parse(AppConfig.apiBaseUrl).resolve(info.url)),
      );
    } catch (e) {
      throw UpdateException('update_download_failed', '$e');
    }
    if (response.statusCode != 200) {
      throw UpdateException('update_download_failed', 'HTTP ${response.statusCode}');
    }
    final total = response.contentLength ?? info.size;
    final sink = file.openWrite();
    final hashSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(hashSink);
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } catch (e) {
      throw UpdateException('update_download_failed', '$e');
    } finally {
      await sink.close();
      hasher.close();
    }
    if (hashSink.value.toString() != info.sha256) {
      await file.delete();
      throw const UpdateException('update_checksum');
    }
    return file;
  }

  /// Starts the installer and quits so it can replace the program files.
  Future<void> install(File installer) async {
    if (!_isWindows) throw const UpdateException('update_unsupported');
    await _start(installer.path, installerArguments);
    _exit();
  }

  static Future<void> _startDetached(String executable, List<String> arguments) =>
      Process.start(executable, arguments, mode: ProcessStartMode.detached);
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

final updateServiceProvider = Provider<UpdateService>(
  (ref) =>
      UpdateService(api: ref.watch(apiClientProvider), httpClient: ref.watch(httpClientProvider)),
);

/// Checked once per app run; null = up to date / server unreachable.
final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  try {
    return await ref.watch(updateServiceProvider).check();
  } on AppException {
    return null;
  }
});

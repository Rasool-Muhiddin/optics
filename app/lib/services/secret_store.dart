import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the API token and the device key live (CLAUDE.md P10: never in a plain file).
///
/// - Windows: a file encrypted with **DPAPI** (`CryptProtectData`, current Windows user).
/// - macOS: the login **Keychain** (`security` tool).
/// - Linux: **libsecret** (`secret-tool`); without it (minimal dev boxes) the values stay in
///   memory + a 0600 file next to the auth file, and [isEncrypted] is false.
abstract class SecretStore {
  Future<String?> read(String key);

  /// `null` deletes the value.
  Future<void> write(String key, String? value);

  bool get isEncrypted;

  /// The right store for this OS.
  static Future<SecretStore> platform() async {
    if (Platform.isWindows) return DpapiSecretStore(await _supportFile('optics_secrets.bin'));
    if (Platform.isMacOS) return KeychainSecretStore();
    if (Platform.isLinux) {
      final libsecret = LibsecretSecretStore();
      if (await libsecret.isAvailable()) return libsecret;
      return PlainFileSecretStore(await _supportFile('optics_secrets.json'));
    }
    return PlainFileSecretStore(await _supportFile('optics_secrets.json'));
  }

  static Future<File> _supportFile(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, name));
  }
}

/// Tests (and any caller that brings its own store).
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  bool get isEncrypted => false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

/// JSON map in a file, without encryption (fallback only).
class PlainFileSecretStore implements SecretStore {
  PlainFileSecretStore(this.file);

  final File file;

  @override
  bool get isEncrypted => false;

  Future<Map<String, String>> _load() async {
    if (!await file.exists()) return {};
    try {
      return (jsonDecode(await file.readAsString()) as Map).cast<String, String>();
    } on FormatException {
      return {};
    }
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, String? value) async {
    final data = await _load();
    value == null ? data.remove(key) : data[key] = value;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', file.path]);
  }
}

/// All secrets in one file encrypted with Windows DPAPI for the current user: another
/// Windows account (or a copied file on another PC) cannot decrypt it.
class DpapiSecretStore implements SecretStore {
  DpapiSecretStore(this.file, {Dpapi? dpapi}) : _dpapi = dpapi ?? Dpapi();

  final File file;
  final Dpapi _dpapi;

  @override
  bool get isEncrypted => true;

  Future<Map<String, String>> _load() async {
    if (!await file.exists()) return {};
    try {
      final plain = _dpapi.unprotect(await file.readAsBytes());
      return (jsonDecode(utf8.decode(plain)) as Map).cast<String, String>();
    } catch (_) {
      return {}; // unreadable (other user / corrupted): behave as "not activated"
    }
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, String? value) async {
    final data = await _load();
    value == null ? data.remove(key) : data[key] = value;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(_dpapi.protect(utf8.encode(jsonEncode(data))), flush: true);
    await tmp.rename(file.path);
  }
}

/// macOS login Keychain via `/usr/bin/security` (generic passwords, service `optics-desktop`).
class KeychainSecretStore implements SecretStore {
  static const service = 'optics-desktop';

  @override
  bool get isEncrypted => true;

  @override
  Future<String?> read(String key) async {
    final r = await Process.run('security', [
      'find-generic-password',
      '-s',
      service,
      '-a',
      key,
      '-w',
    ]);
    return r.exitCode == 0 ? (r.stdout as String).trim() : null;
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      await Process.run('security', ['delete-generic-password', '-s', service, '-a', key]);
      return;
    }
    final r = await Process.run('security', [
      'add-generic-password', '-U', '-s', service, '-a', key, '-w', value, //
    ]);
    if (r.exitCode != 0) throw FileSystemException('Keychain write failed: ${r.stderr}');
  }
}

/// Linux Secret Service (GNOME Keyring / KWallet) via `secret-tool` (package libsecret-tools).
class LibsecretSecretStore implements SecretStore {
  static const service = 'optics-desktop';

  @override
  bool get isEncrypted => true;

  Future<bool> isAvailable() async {
    try {
      final r = await Process.run('secret-tool', ['--version']);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<String?> read(String key) async {
    final r = await Process.run('secret-tool', ['lookup', 'service', service, 'key', key]);
    final out = (r.stdout as String).trim();
    return r.exitCode == 0 && out.isNotEmpty ? out : null;
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      await Process.run('secret-tool', ['clear', 'service', service, 'key', key]);
      return;
    }
    final process = await Process.start('secret-tool', [
      'store', '--label=Optics desktop ($key)', 'service', service, 'key', key, //
    ]);
    process.stdin.write(value);
    await process.stdin.close();
    if (await process.exitCode != 0) throw const FileSystemException('libsecret write failed');
  }
}

// --- DPAPI (crypt32.dll) -----------------------------------------------------------------

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptNative =
    Int32 Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Void> description,
      Pointer<_DataBlob> entropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<_DataBlob> dataOut,
    );
typedef _CryptDart =
    int Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Void> description,
      Pointer<_DataBlob> entropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      int flags,
      Pointer<_DataBlob> dataOut,
    );
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> mem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> mem);

/// `CryptProtectData` / `CryptUnprotectData` for the current Windows user.
class Dpapi {
  static const _uiForbidden = 0x1;

  /// Extra entropy so other apps of the same user cannot simply unprotect our blob.
  static final _entropy = utf8.encode('tera-optics-desktop-v1');

  Uint8List protect(List<int> data) => _call('CryptProtectData', data);

  Uint8List unprotect(List<int> data) => _call('CryptUnprotectData', data);

  Uint8List _call(String function, List<int> data) {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final fn = crypt32.lookupFunction<_CryptNative, _CryptDart>(function);
    final localFree = kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
    return using((arena) {
      Pointer<_DataBlob> blob(List<int> bytes) {
        final ptr = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
        ptr.asTypedList(bytes.length).setAll(0, bytes);
        return arena<_DataBlob>()
          ..ref.cbData = bytes.length
          ..ref.pbData = ptr;
      }

      final input = blob(data);
      final entropy = blob(_entropy);
      final output = arena<_DataBlob>();
      final ok = fn(input, nullptr, entropy, nullptr, nullptr, _uiForbidden, output);
      if (ok == 0) throw const FileSystemException('DPAPI failed');
      try {
        return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      } finally {
        localFree(output.ref.pbData.cast());
      }
    });
  }
}

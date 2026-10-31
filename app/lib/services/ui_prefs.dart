import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Per-device UI preferences (appearance only — no business data).
///
/// Stored in `optics_ui.json` next to the auth file. Opened in `main()`; tests and anything
/// that does not override [uiPrefsProvider] get an in-memory copy.
class UiPrefs {
  UiPrefs._(this._path, this._data);

  /// In-memory prefs (tests, or when the file cannot be used).
  UiPrefs.memory() : _path = null, _data = {};

  final String? _path;
  final Map<String, dynamic> _data;

  static const fileName = 'optics_ui.json';

  static Future<UiPrefs> open() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final path = p.join(dir.path, fileName);
      final file = File(path);
      var data = <String, dynamic>{};
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) data = decoded;
      }
      return UiPrefs._(path, data);
    } catch (_) {
      return UiPrefs.memory();
    }
  }

  ThemeMode get themeMode => switch (_data['theme_mode']) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  bool get sidebarCollapsed => _data['sidebar_collapsed'] == true;

  Future<void> setThemeMode(ThemeMode mode) => _set('theme_mode', mode.name);

  Future<void> setSidebarCollapsed(bool value) => _set('sidebar_collapsed', value);

  Future<void> _set(String key, Object value) async {
    _data[key] = value;
    final path = _path;
    if (path == null) return;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_data), flush: true);
    } catch (_) {
      // Appearance prefs are best-effort.
    }
  }
}

final uiPrefsProvider = Provider<UiPrefs>((ref) => UiPrefs.memory());

/// Light / dark / follow the system.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(uiPrefsProvider).themeMode;

  void set(ThemeMode mode) {
    state = mode;
    ref.read(uiPrefsProvider).setThemeMode(mode);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Sidebar shown as an icon rail (user choice; narrow windows always use the rail).
class SidebarCollapsedController extends Notifier<bool> {
  @override
  bool build() => ref.read(uiPrefsProvider).sidebarCollapsed;

  void toggle() {
    state = !state;
    ref.read(uiPrefsProvider).setSidebarCollapsed(state);
  }
}

final sidebarCollapsedProvider = NotifierProvider<SidebarCollapsedController, bool>(
  SidebarCollapsedController.new,
);

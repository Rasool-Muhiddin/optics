import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/cache/cache_database.dart';
import 'services/auth_storage.dart';
import 'services/ui_prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cache = await CacheDatabase.open();
  final authStorage = await AuthStorage.open();
  final uiPrefs = await UiPrefs.open();

  runApp(
    ProviderScope(
      overrides: [
        cacheDatabaseProvider.overrideWithValue(cache),
        authStorageProvider.overrideWithValue(authStorage),
        uiPrefsProvider.overrideWithValue(uiPrefs),
      ],
      child: const OpticsApp(),
    ),
  );
}

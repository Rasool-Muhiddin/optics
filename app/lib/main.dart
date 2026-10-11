import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/cache/cache_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cache = await CacheDatabase.open();

  runApp(
    ProviderScope(
      overrides: [cacheDatabaseProvider.overrideWithValue(cache)],
      child: const OpticsApp(),
    ),
  );
}

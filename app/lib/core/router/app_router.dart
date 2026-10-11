import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../screens/home/home_screen.dart';

/// Route paths. Feature screens register here as they are built.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen())],
  );
  ref.onDispose(router.dispose);
  return router;
});

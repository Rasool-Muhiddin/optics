import 'package:flutter/material.dart';

import '../../core/strings/app_strings.dart';
import '../../widgets/connection_status_banner.dart';

/// Placeholder landing screen. P1 replaces it with the main layout + sidebar.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appTitle)),
      body: Column(
        children: [
          const ConnectionStatusBanner(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppStrings.welcome, style: textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(AppStrings.scaffoldReady, style: textTheme.bodyLarge),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

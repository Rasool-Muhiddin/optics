import 'package:flutter/material.dart';

import '../../core/strings/app_strings.dart';

/// Shown while the stored session is being checked.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text(AppStrings.loading)],
        ),
      ),
    );
  }
}

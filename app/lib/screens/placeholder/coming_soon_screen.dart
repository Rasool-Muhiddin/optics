import 'package:flutter/material.dart';

import '../../core/strings/app_strings.dart';

/// Stand-in for sidebar sections built in later roadmap phases.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(AppStrings.comingSoon, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}

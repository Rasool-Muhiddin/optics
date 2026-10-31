import 'package:flutter/material.dart';

import '../../core/strings/app_strings.dart';
import '../../widgets/ui.dart';

/// Stand-in for sidebar sections built in later roadmap phases.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.construction_outlined,
      title: title,
      message: AppStrings.comingSoon,
    );
  }
}

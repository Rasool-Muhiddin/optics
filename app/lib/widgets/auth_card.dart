import 'package:flutter/material.dart';

import '../core/strings/app_strings.dart';
import 'connection_status_banner.dart';

/// Centered card layout shared by the activation and login screens.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          const ConnectionStatusBanner(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(Icons.visibility, size: 48, color: theme.colorScheme.primary),
                          const SizedBox(height: 8),
                          Text(
                            AppStrings.appTitle,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              subtitle!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                          const SizedBox(height: 24),
                          child,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error line under a form (Arabic message from [errorMessageFor]).
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message!,
        key: const Key('form-error'),
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.error),
      ),
    );
  }
}

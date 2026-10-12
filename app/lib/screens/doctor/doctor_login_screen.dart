import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_messages.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../services/auth_controller.dart';
import '../../widgets/auth_card.dart';

/// Doctor account login (no device activation: doctors are not tied to a lab).
class DoctorLoginScreen extends ConsumerStatefulWidget {
  const DoctorLoginScreen({super.key});

  @override
  ConsumerState<DoctorLoginScreen> createState() => _DoctorLoginScreenState();
}

class _DoctorLoginScreenState extends ConsumerState<DoctorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).doctorLogin(_username.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activated = ref.watch(authControllerProvider).value is! NeedsActivation;
    return AuthCard(
      title: AppStrings.doctorLogin,
      subtitle: AppStrings.doctorLoginHint,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('doctor-username'),
              controller: _username,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: AppStrings.username,
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? AppStrings.usernameRequired : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('doctor-password'),
              controller: _password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: AppStrings.password,
                prefixIcon: Icon(Icons.lock),
              ),
              validator: (v) => (v == null || v.isEmpty) ? AppStrings.passwordRequired : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            FormErrorText(_error),
            FilledButton(
              key: const Key('doctor-login-button'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
                  : const Text(AppStrings.login),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => context.go(activated ? AppRoutes.login : AppRoutes.activate),
              child: const Text(AppStrings.backToLab),
            ),
          ],
        ),
      ),
    );
  }
}

/// "I am a doctor" link shown under the activation and lab login forms.
class DoctorLoginLink extends StatelessWidget {
  const DoctorLoginLink({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const Key('go-doctor-login'),
    icon: const Icon(Icons.medical_services_outlined, size: 18),
    label: const Text(AppStrings.iAmDoctor),
    onPressed: () => context.go(AppRoutes.doctorLogin),
  );
}

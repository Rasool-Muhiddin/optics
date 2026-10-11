import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/strings/app_strings.dart';
import '../../services/auth_controller.dart';
import '../../widgets/auth_card.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Why the previous session ended (expired license, revoked token…), if known.
    final state = ref.read(authControllerProvider).value;
    if (state is LoggedOut && state.error != null) _error = errorMessageFor(state.error!);
  }

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
      await ref.read(authControllerProvider.notifier).login(_username.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider).value;
    final labName = state is LoggedOut ? state.labName : '';
    return AuthCard(
      title: AppStrings.loginTitle,
      subtitle: labName.isEmpty ? null : labName,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('login-username'),
              controller: _username,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: AppStrings.username,
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? AppStrings.usernameRequired : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('login-password'),
              controller: _password,
              obscureText: _obscure,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: AppStrings.password,
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? AppStrings.passwordRequired : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            FormErrorText(_error),
            FilledButton(
              key: const Key('login-button'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
                  : const Text(AppStrings.login),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => ref.read(authControllerProvider.notifier).reactivate(),
              child: const Text(AppStrings.reactivate),
            ),
          ],
        ),
      ),
    );
  }
}

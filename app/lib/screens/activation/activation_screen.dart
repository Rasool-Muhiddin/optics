import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/strings/app_strings.dart';
import '../../services/auth_controller.dart';
import '../../widgets/auth_card.dart';

/// First run: link this installation to a lab with the code Tera provides.
class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).activate(_code.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      title: AppStrings.activationTitle,
      subtitle: AppStrings.activationHint,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('activation-code'),
              controller: _code,
              autofocus: true,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: AppStrings.activationCode,
                prefixIcon: Icon(Icons.key),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? AppStrings.activationCodeRequired : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            FormErrorText(_error),
            FilledButton(
              key: const Key('activate-button'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
                  : const Text(AppStrings.activate),
            ),
          ],
        ),
      ),
    );
  }
}

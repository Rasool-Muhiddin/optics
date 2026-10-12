import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/reports_repository.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';

/// Picks an image file; returns (bytes, filename) or null. Overridable in tests.
typedef LogoPicker = Future<({Uint8List bytes, String name})?> Function();

Future<({Uint8List bytes, String name})?> pickLogoFile() async {
  const group = XTypeGroup(label: 'images', extensions: ['png', 'jpg', 'jpeg']);
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  return (bytes: await file.readAsBytes(), name: file.name);
}

final logoPickerProvider = Provider<LogoPicker>((ref) => pickLogoFile);

/// Lab settings (owner only): name, phone, address, logo, print header/footer, staff
/// discount limit. Saved with `PATCH lab/`; the session is then reloaded so prints use it.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _lab = ref.read(sessionProvider)!.lab;
  late final _name = TextEditingController(text: _lab.name);
  late final _phone = TextEditingController(text: _lab.phone);
  late final _address = TextEditingController(text: _lab.address);
  late final _header = TextEditingController(text: _lab.printHeader);
  late final _footer = TextEditingController(text: _lab.printFooter);
  late final _discount = TextEditingController(text: _plain(_lab.maxDiscountPercent));
  bool _busy = false;
  Object? _error;

  static String _plain(String v) {
    final n = double.tryParse(v);
    if (n == null) return v;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _header, _footer, _discount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await ref.read(authControllerProvider.notifier).refreshSession();
      if (mounted) showSnack(context, AppStrings.settingsSaved);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    await _run(
      () => ref.read(reportsRepositoryProvider).saveLabSettings({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'print_header': _header.text.trim(),
        'print_footer': _footer.text.trim(),
        'max_discount_percent': _discount.text.trim(),
      }),
    );
  }

  Future<void> _chooseLogo() async {
    final picked = await ref.read(logoPickerProvider)();
    if (picked == null) return;
    await _run(() => ref.read(reportsRepositoryProvider).uploadLogo(picked.bytes, picked.name));
  }

  @override
  Widget build(BuildContext context) {
    final logo = ref.watch(sessionProvider)?.lab.logo;
    final error = _error;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PageHeader(
          title: AppStrings.settingsTitle,
          actions: [
            FilledButton.icon(
              key: const Key('settings-save'),
              icon: const Icon(Icons.save_outlined),
              label: const Text(AppStrings.save),
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FieldGrid(
                        children: [
                          TextFormField(
                            key: const Key('settings-name'),
                            controller: _name,
                            decoration: const InputDecoration(labelText: AppStrings.labName),
                            validator: Inputs.requiredText,
                          ),
                          TextFormField(
                            key: const Key('settings-phone'),
                            controller: _phone,
                            decoration: const InputDecoration(labelText: AppStrings.phone),
                          ),
                          TextFormField(
                            controller: _address,
                            decoration: const InputDecoration(labelText: AppStrings.address),
                          ),
                          TextFormField(
                            key: const Key('settings-discount'),
                            controller: _discount,
                            inputFormatters: Inputs.money,
                            decoration: const InputDecoration(
                              labelText: AppStrings.maxDiscountPercent,
                              helperText: AppStrings.maxDiscountHint,
                            ),
                            validator: (v) {
                              final n = double.tryParse(v?.trim() ?? '');
                              return n == null || n < 0 || n > 100
                                  ? AppStrings.invalidNumber
                                  : null;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('settings-header'),
                        controller: _header,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: AppStrings.printHeader),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('settings-footer'),
                        controller: _footer,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: AppStrings.printFooter),
                      ),
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: AppStrings.logo,
                          helperText: AppStrings.logoHint,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                logo == null || logo.isEmpty
                                    ? AppStrings.none
                                    : logo.split('/').last,
                                textDirection: TextDirection.ltr,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton.icon(
                              key: const Key('settings-logo'),
                              icon: const Icon(Icons.image_outlined),
                              label: const Text(AppStrings.chooseLogo),
                              onPressed: _busy ? null : _chooseLogo,
                            ),
                            if (logo != null && logo.isNotEmpty)
                              TextButton(
                                key: const Key('settings-remove-logo'),
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => ref.read(reportsRepositoryProvider).saveLabSettings({
                                          'remove_logo': true,
                                        }),
                                      ),
                                child: const Text(AppStrings.removeLogo),
                              ),
                          ],
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            errorMessageFor(error),
                            key: const Key('settings-error'),
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

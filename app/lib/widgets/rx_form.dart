import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors/error_messages.dart';
import '../core/optics/powers.dart';
import '../core/strings/app_strings.dart';
import '../models/patients.dart';
import '../screens/inventory/product_form_dialog.dart' show AttributeSpec;

/// Text controllers of one eye.
class EyeControllers {
  final sph = TextEditingController();
  final cyl = TextEditingController();
  final axis = TextEditingController();
  final add = TextEditingController();
  final prism = TextEditingController();
  final va = TextEditingController();
  String base = '';

  List<TextEditingController> get all => [sph, cyl, axis, add, prism, va];

  void load(EyeRx e) {
    sph.text = e.sph == null ? '' : Powers.format(e.sph);
    final cylValue = double.tryParse(e.cyl ?? '') ?? 0;
    cyl.text = cylValue == 0 ? '' : Powers.format(e.cyl);
    axis.text = e.axis?.toString() ?? '';
    add.text = e.add == null ? '' : Powers.format(e.add);
    prism.text = e.prism ?? '';
    va.text = e.va;
    base = e.base;
  }

  bool get hasPower => [sph, cyl, axis, add, prism].any((c) => c.text.trim().isNotEmpty);

  /// Field → Arabic error, mirroring `apps/patients/rx.py`.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (!hasPower) return errors;
    final s = Powers.parse(sph.text);
    if (sph.text.trim().isEmpty) {
      errors['sph'] = AppStrings.sphRequired;
    } else if (s == null || !Powers.validSph(s)) {
      errors['sph'] = AppStrings.invalidPower;
    }
    final c = cyl.text.trim().isEmpty ? 0.0 : Powers.parse(cyl.text);
    if (c == null || !Powers.validCyl(c)) errors['cyl'] = AppStrings.invalidPower;
    if (c != null && c != 0) {
      final a = int.tryParse(axis.text.trim());
      if (axis.text.trim().isEmpty) {
        errors['axis'] = AppStrings.axisRequired;
      } else if (a == null || !Powers.validAxis(a)) {
        errors['axis'] = AppStrings.invalidAxis;
      }
    }
    if (add.text.trim().isNotEmpty) {
      final a = Powers.parse(add.text);
      if (a == null || (a != 0 && !Powers.validAdd(a))) errors['add'] = AppStrings.invalidPower;
    }
    if (prism.text.trim().isNotEmpty) {
      final pr = Powers.parse(prism.text);
      if (pr == null || pr < 0 || pr > 20 || !Powers.isQuarter(pr)) {
        errors['prism'] = AppStrings.invalidPower;
      } else if (pr > 0 && base.isEmpty) {
        errors['base'] = AppStrings.baseRequired;
      }
    }
    return errors;
  }

  Map<String, dynamic> toJson(String eye) {
    String? num2(TextEditingController c) => Powers.parse(c.text)?.toStringAsFixed(2);

    final cylValue = Powers.parse(cyl.text) ?? 0;
    final addValue = Powers.parse(add.text) ?? 0;
    final prismValue = Powers.parse(prism.text) ?? 0;
    return {
      '${eye}_sph': num2(sph),
      '${eye}_cyl': hasPower ? cylValue.toStringAsFixed(2) : null,
      '${eye}_axis': cylValue == 0 ? null : int.tryParse(axis.text.trim()),
      '${eye}_add': addValue == 0 ? null : addValue.toStringAsFixed(2),
      '${eye}_prism': prismValue == 0 ? null : prismValue.toStringAsFixed(2),
      '${eye}_base': prismValue == 0 ? '' : base,
      '${eye}_va': va.text.trim(),
    };
  }

  /// Plus ⇄ minus cylinder in place.
  void transpose() {
    final s = Powers.parse(sph.text);
    final c = Powers.parse(cyl.text);
    if (s == null || c == null || c == 0) return;
    final t = Powers.transpose(s, c, int.tryParse(axis.text.trim()));
    sph.text = Powers.format(t.sph);
    cyl.text = Powers.format(t.cyl);
    axis.text = t.axis?.toString() ?? '';
  }

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}

/// All values of the OD/OS prescription form.
class RxFormController {
  final od = EyeControllers();
  final os = EyeControllers();
  final pdDistance = TextEditingController();
  final pdNear = TextEditingController();
  final pdOd = TextEditingController();
  final pdOs = TextEditingController();
  final frameNotes = TextEditingController();
  final notes = TextEditingController();
  String usage = 'distance';
  String lensDesign = '';
  String lensIndex = '';
  final Set<String> coatings = {};

  void load(Prescription? rx) {
    if (rx == null) return;
    od.load(rx.od);
    os.load(rx.os);
    pdDistance.text = rx.pdDistance ?? '';
    pdNear.text = rx.pdNear ?? '';
    pdOd.text = rx.pdOd ?? '';
    pdOs.text = rx.pdOs ?? '';
    frameNotes.text = rx.frameNotes;
    notes.text = rx.notes;
    usage = rx.usage;
    lensDesign = rx.lensDesign;
    lensIndex = rx.lensIndex;
    coatings
      ..clear()
      ..addAll(rx.lensCoatings);
  }

  bool get isEmpty => !od.hasPower && !os.hasPower;

  /// Keys like `od_sph`, `pd_distance`, `rx` (whole form).
  Map<String, String> validate() {
    final errors = <String, String>{
      for (final e in od.validate().entries) 'od_${e.key}': e.value,
      for (final e in os.validate().entries) 'os_${e.key}': e.value,
    };
    if (isEmpty) errors['rx'] = AppStrings.errRxEmpty;
    void pd(String key, TextEditingController c, double min, double max) {
      if (c.text.trim().isEmpty) return;
      final v = Powers.parse(c.text);
      if (v == null || v < min || v > max || ((v * 2) - (v * 2).round()).abs() > 1e-6) {
        errors[key] = AppStrings.invalidPd;
      }
    }

    pd('pd_distance', pdDistance, 40, 85);
    pd('pd_near', pdNear, 40, 85);
    pd('pd_od', pdOd, 20, 45);
    pd('pd_os', pdOs, 20, 45);
    return errors;
  }

  Map<String, dynamic> toJson() {
    String? pd(TextEditingController c) => Powers.parse(c.text)?.toStringAsFixed(1);
    return {
      ...od.toJson('od'),
      ...os.toJson('os'),
      'pd_distance': pd(pdDistance),
      'pd_near': pd(pdNear),
      'pd_od': pd(pdOd),
      'pd_os': pd(pdOs),
      'usage': usage,
      'lens_design': lensDesign,
      'lens_index': lensIndex,
      'lens_coatings': coatings.toList(),
      'frame_notes': frameNotes.text.trim(),
      'notes': notes.text.trim(),
    };
  }

  void dispose() {
    od.dispose();
    os.dispose();
    for (final c in [pdDistance, pdNear, pdOd, pdOs, frameNotes, notes]) {
      c.dispose();
    }
  }
}

/// OD/OS table (SPH CYL AXIS ADD PRISM BASE VA) + PD + lens recommendation.
///
/// [errors] are local validation messages; [serverError] + [serverPath] show the
/// server's per-field codes (e.g. path `['prescription']` inside an exam).
class RxForm extends StatefulWidget {
  const RxForm({
    super.key,
    required this.controller,
    this.errors = const {},
    this.serverError,
    this.serverPath = const [],
  });

  final RxFormController controller;
  final Map<String, String> errors;
  final Object? serverError;
  final List<String> serverPath;

  @override
  State<RxForm> createState() => _RxFormState();
}

class _RxFormState extends State<RxForm> {
  RxFormController get c => widget.controller;

  String? _error(String key) =>
      widget.errors[key] ?? fieldCodeMessage(widget.serverError, [...widget.serverPath, key]);

  Widget _cell(String eye, String field, TextEditingController controller, {double width = 76}) {
    final isAxis = field == 'axis';
    final isVa = field == 'va';
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: TextField(
          key: Key('rx-${eye}_$field'),
          controller: controller,
          textAlign: TextAlign.center,
          inputFormatters: isVa
              ? null
              : [FilteringTextInputFormatter.allow(RegExp(isAxis ? r'[0-9]' : r'[-+0-9.]'))],
          decoration: InputDecoration(
            isDense: true,
            errorText: _error('${eye}_$field'),
            errorMaxLines: 2,
            errorStyle: const TextStyle(fontSize: 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          ),
          onEditingComplete: () {
            if (!isAxis && !isVa && controller.text.trim().isNotEmpty) {
              final v = Powers.parse(controller.text);
              if (v != null && field != 'prism') controller.text = Powers.format(v);
            }
            FocusScope.of(context).nextFocus();
          },
        ),
      ),
    );
  }

  Widget _eyeRow(String eye, EyeControllers e, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        _cell(eye, 'sph', e.sph),
        _cell(eye, 'cyl', e.cyl),
        _cell(eye, 'axis', e.axis, width: 64),
        _cell(eye, 'add', e.add),
        _cell(eye, 'prism', e.prism, width: 64),
        SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: DropdownButtonFormField<String>(
              key: Key('rx-${eye}_base'),
              initialValue: e.base,
              isDense: true,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                errorText: _error('${eye}_base'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('—')),
                for (final b in AppStrings.prismBasesLatin.entries)
                  DropdownMenuItem(value: b.key, child: Text(b.value)),
              ],
              onChanged: (v) => setState(() => e.base = v ?? ''),
            ),
          ),
        ),
        _cell(eye, 'va', e.va),
        IconButton(
          key: Key('rx-transpose-$eye'),
          tooltip: AppStrings.transposeHint,
          icon: const Icon(Icons.swap_horiz),
          onPressed: () => setState(e.transpose),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget head(String t, double w) => SizedBox(
      width: w,
      child: Text(t, textAlign: TextAlign.center, style: theme.textTheme.labelMedium),
    );
    Widget pdField(String key, String label, TextEditingController controller) => SizedBox(
      width: 120,
      child: TextField(
        key: Key('rx-$key'),
        controller: controller,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(labelText: label, errorText: _error(key)),
      ),
    );
    final rxError =
        widget.errors['rx'] ??
        fieldCodeMessage(widget.serverError, [...widget.serverPath, 'od_sph']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    head('', 64),
                    head('SPH', 76),
                    head('CYL', 76),
                    head('AXIS', 64),
                    head('ADD', 76),
                    head('PRISM', 64),
                    head('BASE', 76),
                    head('VA', 76),
                    head('±', 48),
                  ],
                ),
                _eyeRow('od', c.od, 'OD (R)'),
                _eyeRow('os', c.os, 'OS (L)'),
              ],
            ),
          ),
        ),
        if (widget.errors['rx'] != null || (rxError != null && c.isEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(rxError ?? '', style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            pdField('pd_distance', AppStrings.pdDistance, c.pdDistance),
            pdField('pd_near', AppStrings.pdNear, c.pdNear),
            pdField('pd_od', AppStrings.pdRight, c.pdOd),
            pdField('pd_os', AppStrings.pdLeft, c.pdOs),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: c.usage,
                decoration: const InputDecoration(labelText: AppStrings.usage),
                items: [
                  for (final u in AppStrings.usages.entries)
                    DropdownMenuItem(value: u.key, child: Text(u.value)),
                ],
                onChanged: (v) => setState(() => c.usage = v ?? 'distance'),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: c.lensDesign,
                decoration: const InputDecoration(labelText: AppStrings.lensDesign),
                items: [
                  const DropdownMenuItem(value: '', child: Text(AppStrings.none)),
                  for (final d in const ['single_vision', 'bifocal', 'progressive', 'office'])
                    DropdownMenuItem(value: d, child: Text(AppStrings.choiceLabels[d]!)),
                ],
                onChanged: (v) => setState(() => c.lensDesign = v ?? ''),
              ),
            ),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: c.lensIndex,
                decoration: const InputDecoration(labelText: AppStrings.lensIndex),
                items: [
                  const DropdownMenuItem(value: '', child: Text(AppStrings.none)),
                  for (final i in AttributeSpec.lensIndexes)
                    DropdownMenuItem(value: i, child: Text(i)),
                ],
                onChanged: (v) => setState(() => c.lensIndex = v ?? ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final coating in const [
              'ar',
              'blue_cut',
              'photochromic',
              'hard_coat',
              'uv',
              'polarized',
              'tint',
            ])
              FilterChip(
                label: Text(AppStrings.choiceLabels[coating]!),
                selected: c.coatings.contains(coating),
                onSelected: (on) =>
                    setState(() => on ? c.coatings.add(coating) : c.coatings.remove(coating)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: c.frameNotes,
          decoration: const InputDecoration(labelText: AppStrings.frameNotes),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: c.notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: AppStrings.notes),
        ),
      ],
    );
  }
}

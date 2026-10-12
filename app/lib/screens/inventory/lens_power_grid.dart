import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/optics/powers.dart';
import '../../models/catalog.dart';

/// SPH rows × CYL columns of a lens product's powers (one ADD at a time).
///
/// View mode: each cell shows the stock (red = 0, amber = low) and [onTap] opens it.
/// Entry mode ([controllers] non-null): each existing power gets a quantity field.
class LensPowerGrid extends StatelessWidget {
  const LensPowerGrid({
    super.key,
    required this.variants,
    this.onTap,
    this.controllers,
    this.lowThreshold = 1,
  });

  final List<LensVariant> variants;
  final void Function(LensVariant variant)? onTap;
  final Map<int, TextEditingController>? controllers;
  final int lowThreshold;

  static const double _cellWidth = 64;
  static const double _cellHeight = 34;

  /// Sorted distinct SPH (plus first, like printed stock charts) and CYL (0 → most minus).
  static ({List<double> sphs, List<double> cyls}) axes(List<LensVariant> variants) {
    final sphs = {for (final v in variants) v.sph}.toList()..sort((a, b) => b.compareTo(a));
    final cyls = {for (final v in variants) v.cyl}.toList()..sort((a, b) => b.compareTo(a));
    return (sphs: sphs, cyls: cyls);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (:sphs, :cyls) = axes(variants);
    final byPower = {for (final v in variants) (v.sph, v.cyl): v};
    final headerStyle = theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold);

    Widget header(String text) => Container(
      width: _cellWidth,
      height: _cellHeight,
      alignment: Alignment.center,
      color: scheme.surfaceContainerHighest,
      child: Text(text, style: headerStyle, textDirection: TextDirection.ltr),
    );

    Widget cell(LensVariant? v) {
      if (v == null) {
        return Container(width: _cellWidth, height: _cellHeight, color: scheme.surfaceContainerLow);
      }
      final controller = controllers?[v.id];
      if (controller != null) {
        return SizedBox(
          width: _cellWidth,
          height: _cellHeight,
          child: TextField(
            key: Key('grid-input-${v.id}'),
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
            ),
          ),
        );
      }
      final color = !v.isActive
          ? scheme.surfaceContainerHigh
          : v.quantity <= 0
          ? scheme.errorContainer
          : v.quantity <= lowThreshold
          ? Colors.amber.shade100
          : Colors.green.shade50;
      return InkWell(
        key: Key('grid-cell-${v.id}'),
        onTap: onTap == null ? null : () => onTap!(v),
        child: Container(
          width: _cellWidth,
          height: _cellHeight,
          alignment: Alignment.center,
          color: color,
          child: Text('${v.quantity}', style: theme.textTheme.bodyMedium),
        ),
      );
    }

    final border = BorderSide(color: theme.dividerColor, width: 0.5);
    return Directionality(
      // Powers read left-to-right like printed charts, even in the RTL UI.
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const FixedColumnWidth(_cellWidth),
          border: TableBorder(
            horizontalInside: border,
            verticalInside: border,
            top: border,
            bottom: border,
            left: border,
            right: border,
          ),
          children: [
            TableRow(
              children: [header('SPH \\ CYL'), for (final c in cyls) header(Powers.format(c))],
            ),
            for (final s in sphs)
              TableRow(
                children: [header(Powers.format(s)), for (final c in cyls) cell(byPower[(s, c)])],
              ),
          ],
        ),
      ),
    );
  }
}

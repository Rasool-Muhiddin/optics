/// Client-side optical power helpers (mirror of `apps/core/optics.py`; the server validates).
class Powers {
  const Powers._();

  static const double sphMin = -30, sphMax = 30;
  static const double cylMin = -10, cylMax = 10;
  static const double addMin = 0.5, addMax = 4;

  static double? parse(String? text) {
    if (text == null) return null;
    final cleaned = text.trim().replaceAll('+', '').replaceAll('٫', '.').replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(_westernDigits(cleaned));
  }

  static bool isQuarter(double v) => ((v * 4) - (v * 4).round()).abs() < 1e-6;

  static bool inRange(double v, double min, double max) => v >= min - 1e-9 && v <= max + 1e-9;

  static bool validSph(double v) => inRange(v, sphMin, sphMax) && isQuarter(v);
  static bool validCyl(double v) => inRange(v, cylMin, cylMax) && isQuarter(v);
  static bool validAdd(double v) => inRange(v, addMin, addMax) && isQuarter(v);
  static bool validAxis(int v) => v >= 1 && v <= 180;

  /// `-1.25` → `"-1.25"`, `2` → `"+2.00"`, `0` → `"0.00"` (optometric style).
  static String format(Object? value) {
    final v = value is num ? value.toDouble() : parse(value?.toString());
    if (v == null) return '';
    if (v.abs() < 1e-9) return '0.00';
    return '${v > 0 ? '+' : '-'}${v.abs().toStringAsFixed(2)}';
  }

  /// Plus ⇄ minus cylinder: SPH' = SPH + CYL, CYL' = −CYL, AXIS' = AXIS ± 90.
  static ({double sph, double cyl, int? axis}) transpose(double sph, double cyl, int? axis) {
    if (cyl.abs() < 1e-9) return (sph: sph, cyl: 0, axis: null);
    final a = axis ?? 0;
    return (sph: _round(sph + cyl), cyl: _round(-cyl), axis: a <= 90 ? a + 90 : a - 90);
  }

  /// Spherical equivalent (SPH + CYL/2), shown as a hint.
  static double sphericalEquivalent(double sph, double cyl) => _round(sph + cyl / 2);

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  static String _westernDigits(String s) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = arabic.indexOf(ch);
      b.write(i >= 0 ? '$i' : ch);
    }
    return b.toString();
  }
}

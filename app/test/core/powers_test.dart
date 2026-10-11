import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/core/optics/powers.dart';

void main() {
  test('parses signed, Arabic-digit and comma input', () {
    expect(Powers.parse('+1.25'), 1.25);
    expect(Powers.parse('-0,75'), -0.75);
    expect(Powers.parse('٢٫٥٠'), 2.5);
    expect(Powers.parse(''), isNull);
    expect(Powers.parse('abc'), isNull);
  });

  test('validates ranges and quarter steps', () {
    expect(Powers.validSph(-30), isTrue);
    expect(Powers.validSph(-30.25), isFalse);
    expect(Powers.validSph(1.1), isFalse);
    expect(Powers.validCyl(-2.75), isTrue);
    expect(Powers.validAdd(0.25), isFalse);
    expect(Powers.validAdd(2.5), isTrue);
    expect(Powers.validAxis(0), isFalse);
    expect(Powers.validAxis(180), isTrue);
  });

  test('formats optometric style', () {
    expect(Powers.format(2), '+2.00');
    expect(Powers.format('-0.5'), '-0.50');
    expect(Powers.format(0), '0.00');
    expect(Powers.format(null), '');
  });

  test('transposes plus/minus cylinder and back', () {
    final t = Powers.transpose(-1, 2, 90);
    expect((t.sph, t.cyl, t.axis), (1.0, -2.0, 180));
    final back = Powers.transpose(t.sph, t.cyl, t.axis);
    expect((back.sph, back.cyl, back.axis), (-1.0, 2.0, 90));
    expect(Powers.transpose(-1, 0, 30).axis, isNull);
    expect(Powers.sphericalEquivalent(-2, -1), -2.5);
  });
}

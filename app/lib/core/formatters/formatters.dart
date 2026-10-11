import 'package:intl/intl.dart';

import '../strings/app_strings.dart';

/// Display formatters. Money arrives from the API as decimal strings and is
/// never used for arithmetic on the client (the server computes all totals).
class Formatters {
  const Formatters._();

  /// `"125000.00"` → `"125,000 د.ع"`.
  static String money(Object? value, {String currency = AppStrings.currencyIqd, int decimals = 0}) {
    final number = switch (value) {
      null => 0,
      num n => n,
      String s => num.tryParse(s) ?? 0,
      _ => 0,
    };
    final pattern = decimals > 0 ? '#,##0.${'0' * decimals}' : '#,##0';
    return '${NumberFormat(pattern, 'en').format(number)} $currency';
  }

  /// `yyyy/MM/dd` with Western digits (no locale data needed, works offline/in print).
  static String date(DateTime? value) {
    if (value == null) return '';
    final d = value.toLocal();
    return '${d.year}/${_two(d.month)}/${_two(d.day)}';
  }

  /// `yyyy/MM/dd HH:mm`.
  static String dateTime(DateTime? value) {
    if (value == null) return '';
    final d = value.toLocal();
    return '${date(d)} ${_two(d.hour)}:${_two(d.minute)}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

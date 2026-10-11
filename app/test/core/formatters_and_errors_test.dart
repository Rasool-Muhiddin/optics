import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/core/errors/app_exception.dart';
import 'package:optics_app/core/errors/error_messages.dart';
import 'package:optics_app/core/formatters/formatters.dart';
import 'package:optics_app/core/strings/app_strings.dart';

void main() {
  test('money formats API decimal strings in IQD', () {
    expect(Formatters.money('125000.00'), '125,000 د.ع');
    expect(Formatters.money(null), '0 د.ع');
    expect(Formatters.money(1500.5, decimals: 2, currency: r'$'), r'1,500.50 $');
  });

  test('date formats as yyyy/MM/dd', () {
    expect(Formatters.date(DateTime(2026, 3, 7)), '2026/03/07');
    expect(Formatters.date(null), '');
    expect(Formatters.dateTime(DateTime(2026, 3, 7, 9, 5)), '2026/03/07 09:05');
  });

  test('errors map to Arabic messages by code', () {
    expect(errorMessageFor(const OfflineWriteException()), AppStrings.errOfflineWrite);
    expect(errorMessageFor(const NetworkException(timeout: true)), AppStrings.errTimeout);
    expect(
      errorMessageFor(const ApiException(statusCode: 403, code: 'permission_denied')),
      AppStrings.errPermissionDenied,
    );
    expect(
      errorMessageFor(const ApiException(statusCode: 502, code: 'bad_gateway')),
      AppStrings.errServer,
    );
    expect(errorMessageFor(StateError('x')), AppStrings.errUnknown);
  });
}

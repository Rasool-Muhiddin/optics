import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/models/patients.dart';
import 'package:optics_app/services/printing/patient_pdfs.dart';
import 'package:optics_app/widgets/rx_form.dart';

void main() {
  test('empty form needs at least one eye', () {
    final c = RxFormController();
    expect(c.validate(), {'rx': AppStrings.errRxEmpty});
  });

  test('axis required iff cylinder, steps and ranges checked', () {
    final c = RxFormController();
    c.od.sph.text = '-2.10';
    c.od.cyl.text = '-0.75';
    c.os.cyl.text = '-1';
    c.os.axis.text = '90';
    c.pdDistance.text = '30';
    final errors = c.validate();
    expect(errors['od_sph'], AppStrings.invalidPower);
    expect(errors['od_axis'], AppStrings.axisRequired);
    expect(errors['os_sph'], AppStrings.sphRequired);
    expect(errors['pd_distance'], AppStrings.invalidPd);
  });

  test('toJson sends decimals, drops axis without cylinder', () {
    final c = RxFormController();
    c.od.sph.text = '-2';
    c.od.axis.text = '90';
    c.os.sph.text = '+1.25';
    c.os.cyl.text = '-0.5';
    c.os.axis.text = '180';
    c.os.add.text = '2';
    c.pdDistance.text = '63';
    c.coatings.add('ar');
    expect(c.validate(), isEmpty);
    final json = c.toJson();
    expect(json['od_sph'], '-2.00');
    expect(json['od_cyl'], '0.00');
    expect(json['od_axis'], isNull);
    expect(json['os_cyl'], '-0.50');
    expect(json['os_axis'], 180);
    expect(json['os_add'], '2.00');
    expect(json['pd_distance'], '63.0');
    expect(json['lens_coatings'], ['ar']);
  });

  test('transpose flips cylinder sign in place', () {
    final c = RxFormController();
    c.od.sph.text = '-1.00';
    c.od.cyl.text = '+2.00';
    c.od.axis.text = '90';
    c.od.transpose();
    expect((c.od.sph.text, c.od.cyl.text, c.od.axis.text), ('+1.00', '-2.00', '180'));
  });

  test('load shows server values in optometric format', () {
    final c = RxFormController()
      ..load(
        Prescription.fromJson({
          'id': 1,
          'patient': 2,
          'od_sph': '-2.25',
          'od_cyl': '-0.50',
          'od_axis': 170,
          'os_sph': '0.00',
          'os_cyl': '0.00',
          'usage': 'both',
          'lens_coatings': ['blue_cut'],
        }),
      );
    expect((c.od.sph.text, c.od.cyl.text, c.od.axis.text), ('-2.25', '-0.50', '170'));
    expect((c.os.sph.text, c.os.cyl.text), ('0.00', ''));
    expect(c.usage, 'both');
  });

  test('plus-cyl Rx is sent and shown exactly as entered', () {
    final c = RxFormController();
    c.od.sph.text = '-2.50';
    c.od.cyl.text = '+0.50';
    c.od.axis.text = '80';
    expect(c.validate(), isEmpty);
    final json = c.toJson();
    expect((json['od_sph'], json['od_cyl'], json['od_axis']), ('-2.50', '0.50', 80));

    final rx = Prescription.fromJson({
      'id': 1,
      'patient': 2,
      'od_sph': '-2.50',
      'od_cyl': '0.50',
      'od_axis': 80,
    });
    expect(rx.summary, 'OD -2.50 +0.50×80 | OS —');
    expect(PatientPdfs.rxRows(rx)[1].take(4), ['OD (R)', '-2.50', '+0.50', '80°']);
    final loaded = RxFormController()..load(rx);
    expect((loaded.od.sph.text, loaded.od.cyl.text, loaded.od.axis.text), ('-2.50', '+0.50', '80'));
  });
}

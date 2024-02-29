import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive/services/license/licenses/cc.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:reactive_forms/reactive_forms.dart';

const ccActiveLicenses = [
  cc0LicenseMeta,
  ccByLicenseMetaV2,
  ccByNCLicenseMeta,
  ccByNCNDLicenseMeta,
  ccByNCSAMeta,
  ccByNDLicenseMeta,
  ccBySAMeta,
];

const ccDefaultLicense = ccByLicenseMetaV2;

FormGroup createCcTypeForm() => FormGroup({
      'ccTypeField': FormControl<LicenseMeta>(
        validators: [Validators.required],
        value: ccDefaultLicense,
      ),
    });

UdlLicenseParams udlFormToLicenseParams(FormGroup udlForm) {
  final String? licenseFeeAmountString =
      udlForm.control('licenseFeeAmount').value;
  final double? licenseFeeAmount = licenseFeeAmountString == null
      ? null
      : double.tryParse(licenseFeeAmountString);

  final UdlCurrency licenseFeeCurrency =
      udlForm.control('licenseFeeCurrency').value;
  final UdlCommercialUse commercialUse = udlForm.control('commercialUse').value;
  final UdlDerivation derivations = udlForm.control('derivations').value;

  return UdlLicenseParams(
    licenseFeeAmount: licenseFeeAmount,
    licenseFeeCurrency: licenseFeeCurrency,
    commercialUse: commercialUse,
    derivations: derivations,
  );
}

import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:reactive_forms/reactive_forms.dart';

const udlLicenseDefault = udlLicenseMetaV2;

FormGroup createUdlParamsForm() => FormGroup({
      'licenseFeeAmount': FormControl<String>(
        validators: [
          Validators.composeOR([
            Validators.pattern(
              r'^\d+\.?\d*$',
              validationMessage: 'Invalid amount',
            ),
            Validators.equals(''),
          ]),
        ],
      ),
      'licenseFeeCurrency': FormControl<UdlCurrency>(
        validators: [Validators.required],
        value: UdlCurrency.u,
      ),
      'commercialUse': FormControl<UdlCommercialUse>(
        validators: [Validators.required],
        value: UdlCommercialUse.unspecified,
      ),
      'derivations': FormControl<UdlDerivation>(
        validators: [Validators.required],
        value: UdlDerivation.unspecified,
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

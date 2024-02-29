import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:reactive_forms/reactive_forms.dart';

const udlDefaultLicense = udlLicenseMetaV2;

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

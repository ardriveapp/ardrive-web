import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive/services/license/licenses/cc.dart';
import 'package:reactive_forms/reactive_forms.dart';

const ccLicensesEnabled = [
  cc0LicenseMeta,
  ccByLicenseMetaV2,
  ccByNCLicenseMeta,
  ccByNCNDLicenseMeta,
  ccByNCSAMeta,
  ccByNDLicenseMeta,
  ccBySAMeta,
];

/// Starts with no license chosen. A license is recorded with the file for
/// good, and CC0 gives up every right to it, so the uploader picks one rather
/// than inheriting it.
FormGroup createCcTypeForm() => FormGroup({
      'ccTypeField': FormControl<LicenseMeta>(
        validators: [Validators.required],
      ),
    });

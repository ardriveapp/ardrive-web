import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive/services/license/licenses/cc.dart';
import 'package:reactive_forms/reactive_forms.dart';

createCcForm() => FormGroup({
      'ccAttributionField': FormControl<LicenseMeta>(
        validators: [Validators.required],
        value: cc0LicenseMeta,
      ),
    });

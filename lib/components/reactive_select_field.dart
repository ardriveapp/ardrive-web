import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:reactive_forms/reactive_forms.dart';

/// [ArDriveSelectField] bound to a reactive_forms control, in place of
/// [ReactiveDropdownField]: it shows the control's value and errors, sets
/// the value when a choice is made, then calls [onChanged], and is disabled
/// while the control is.
class ReactiveArDriveSelectField<T> extends ReactiveFormField<T, T> {
  ReactiveArDriveSelectField({
    super.key,
    super.formControlName,
    super.formControl,
    super.validationMessages,
    super.showErrors,
    required List<ArDriveChoice<T>> choices,
    String? label,
    String? hintText,
    bool isFieldRequired = false,
    ReactiveFormFieldCallback<T>? onChanged,
  }) : super(
          builder: (field) => ArDriveSelectField<T>(
            choices: choices,
            value: field.value,
            label: label,
            hintText: hintText,
            isFieldRequired: isFieldRequired,
            errorText: field.errorText,
            onChanged: field.control.disabled
                ? null
                : (value) {
                    field.didChange(value);
                    onChanged?.call(field.control);
                  },
          ),
        );
}

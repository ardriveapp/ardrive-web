import 'package:ardrive/components/reactive_select_field.dart';
import 'package:ardrive/components/labeled_input.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/forms/cc.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';

class CcTypeForm extends StatefulWidget {
  const CcTypeForm({super.key, required this.formGroup});

  final FormGroup formGroup;

  @override
  State<CcTypeForm> createState() => _CcTypeFormState();
}

class _CcTypeFormState extends State<CcTypeForm> {
  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ReactiveForm(
      formGroup: widget.formGroup,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: LabeledInput(
                    labelText: 'Type',
                    child: ReactiveArDriveSelectField<LicenseMeta>(
                      formControlName: 'ccTypeField',
                      hintText: appLocalizationsOf(context).chooseALicenseType,
                      onChanged: (e) {
                        setState(() {});
                      },
                      showErrors: (control) => control.dirty && control.invalid,
                      validationMessages:
                          kValidationMessages(appLocalizationsOf(context)),
                      choices: [
                        for (final e in ccLicensesEnabled)
                          ArDriveChoice(value: e, label: e.name),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            ReactiveFormConsumer(
              builder: (_, form, __) {
                final LicenseMeta? selectedLicenseMeta =
                    form.control('ccTypeField').value;

                // Nothing is chosen until the uploader chooses.
                if (selectedLicenseMeta == null) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    selectedLicenseMeta.shortName,
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textMid,
                    ),
                  ),
                );
              },
            ),
          ]),
    );
  }
}

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
    final inputBorder = OutlineInputBorder(
      borderSide: BorderSide(
        color: ArDriveTheme.of(context)
            .themeData
            .colors
            .themeFgDisabled
            .withOpacity(0.3),
        width: 2,
      ),
      borderRadius: BorderRadius.circular(4),
    );

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
                    child: ReactiveDropdownField<LicenseMeta>(
                      formControlName: 'ccTypeField',
                      hint: Text(
                        appLocalizationsOf(context).chooseALicenseType,
                        style: typography.paragraphNormal(
                          color: colorTokens.textMid,
                        ),
                      ),
                      decoration: InputDecoration(
                        enabledBorder: inputBorder,
                        focusedBorder: inputBorder,
                      ),
                      onChanged: (e) {
                        setState(() {});
                      },
                      showErrors: (control) => control.dirty && control.invalid,
                      validationMessages:
                          kValidationMessages(appLocalizationsOf(context)),
                      items: ccLicensesEnabled
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                e.name,
                                style: typography.paragraphNormal(
                                  color: colorTokens.textHigh,
                                ),
                              ),
                            ),
                          )
                          .toList(),
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

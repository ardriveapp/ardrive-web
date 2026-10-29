import 'package:ardrive/components/reactive_select_field.dart';
import 'package:ardrive/components/labeled_input.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';

class UdlParamsForm extends StatefulWidget {
  final FormGroup formGroup;
  final Function onChangeLicenseFee;

  const UdlParamsForm({
    super.key,
    required this.formGroup,
    required this.onChangeLicenseFee,
  });

  @override
  State<UdlParamsForm> createState() => _UdlParamsFormState();
}

class _UdlParamsFormState extends State<UdlParamsForm> {
  @override
  Widget build(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderSide: BorderSide(
        color: ArDriveTheme.of(context).themeData.colorTokens.strokeMid,
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
                Expanded(
                  child: LabeledInput(
                    labelText:
                        // TODO: Localize
                        // appLocalizationsOf(context).udlLicenseFee,
                        'License fee',
                    child: ReactiveTextField(
                      formControlName: 'licenseFeeAmount',
                      cursorColor: ArDriveTheme.of(context)
                          .themeData
                          .colorTokens
                          .textHigh,
                      keyboardType: TextInputType.number,
                      showErrors: (control) => control.dirty && control.invalid,
                      decoration: InputDecoration(
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        focusedBorder: inputBorder,
                      ),
                      onChanged: (s) {
                        widget.onChangeLicenseFee();
                      },
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ),
                Container(
                  width: kMediumDialogWidth * 0.5,
                  padding: const EdgeInsets.only(left: 24),
                  child: LabeledInput(
                    labelText: appLocalizationsOf(context).currency,
                    child: ReactiveArDriveSelectField(
                      formControlName: 'licenseFeeCurrency',
                      showErrors: (control) => control.dirty && control.invalid,
                      validationMessages:
                          kValidationMessages(appLocalizationsOf(context)),
                      choices: [
                        for (final entry in udlCurrencyValues.entries)
                          ArDriveChoice(value: entry.key, label: entry.value),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            LabeledInput(
              labelText:
                  // TODO: Localize
                  // appLocalizationsOf(context).udlCommercialUse,
                  'Commercial use',
              child: ReactiveArDriveSelectField(
                formControlName: 'commercialUse',
                showErrors: (control) => control.dirty && control.invalid,
                validationMessages:
                    kValidationMessages(appLocalizationsOf(context)),
                choices: [
                  for (final entry in udlCommercialUseValues.entries)
                    ArDriveChoice(value: entry.key, label: entry.value),
                ],
              ),
            ),
            LabeledInput(
              labelText:
                  // TODO: Localize
                  // appLocalizationsOf(context).udlDerivations,
                  'Derivations',
              child: ReactiveArDriveSelectField(
                formControlName: 'derivations',
                showErrors: (control) => control.dirty && control.invalid,
                validationMessages:
                    kValidationMessages(appLocalizationsOf(context)),
                choices: [
                  for (final entry in udlDerivationValues.entries)
                    ArDriveChoice(value: entry.key, label: entry.value),
                ],
              ),
            ),
          ]
              .expand(
                (element) => [element, const SizedBox(height: 16)],
              )
              .toList(),
        ));
  }
}

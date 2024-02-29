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
                Expanded(
                  child: LabeledInput(
                    labelText:
                        // TODO: Localize
                        // appLocalizationsOf(context).udlLicenseFee,
                        'License Fee',
                    child: ReactiveTextField(
                      formControlName: 'licenseFeeAmount',
                      cursorColor: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
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
                    child: ReactiveDropdownField(
                      formControlName: 'licenseFeeCurrency',
                      decoration: InputDecoration(
                        enabledBorder: inputBorder,
                        focusedBorder: inputBorder,
                      ),
                      showErrors: (control) => control.dirty && control.invalid,
                      validationMessages:
                          kValidationMessages(appLocalizationsOf(context)),
                      items: udlCurrencyValues.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
            LabeledInput(
              labelText:
                  // TODO: Localize
                  // appLocalizationsOf(context).udlCommercialUse,
                  'Commercial Use',
              child: ReactiveDropdownField(
                formControlName: 'commercialUse',
                decoration: InputDecoration(
                  enabledBorder: inputBorder,
                  focusedBorder: inputBorder,
                ),
                showErrors: (control) => control.dirty && control.invalid,
                validationMessages:
                    kValidationMessages(appLocalizationsOf(context)),
                items: udlCommercialUseValues.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
              ),
            ),
            LabeledInput(
              labelText:
                  // TODO: Localize
                  // appLocalizationsOf(context).udlDerivations,
                  'Derivations',
              child: ReactiveDropdownField(
                formControlName: 'derivations',
                decoration: InputDecoration(
                  enabledBorder: inputBorder,
                  focusedBorder: inputBorder,
                ),
                showErrors: (control) => control.dirty && control.invalid,
                validationMessages:
                    kValidationMessages(appLocalizationsOf(context)),
                items: udlDerivationValues.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
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

import 'dart:async';

import 'package:ardrive/components/reactive_select_field.dart';
import 'package:ardrive/components/labeled_input.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
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

/// Below this width the fee and currency stack instead of sharing a row.
const _kStackBelowWidth = 400.0;

class _UdlParamsFormState extends State<UdlParamsForm> {
  late final AbstractControl<String> _feeControl =
      widget.formGroup.control('licenseFeeAmount') as AbstractControl<String>;
  late final TextEditingController _feeController =
      TextEditingController(text: _feeControl.value);
  StreamSubscription<String?>? _feeSub;

  @override
  void initState() {
    super.initState();
    // Keep the field in step with a reset or a value set from outside.
    _feeSub = _feeControl.valueChanges.listen((value) {
      if ((value ?? '') != _feeController.text) {
        _feeController.text = value ?? '';
      }
    });
  }

  @override
  void dispose() {
    _feeSub?.cancel();
    _feeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReactiveForm(
        formGroup: widget.formGroup,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final fee = LabeledInput(
                  labelText: appLocalizationsOf(context).licenseFeeLabel,
                  child: ArDriveTextFieldNew(
                    controller: _feeController,
                    keyboardType: TextInputType.number,
                    showErrorMessage: _feeControl.dirty && _feeControl.invalid,
                    errorMessage: _feeControl.dirty && _feeControl.invalid
                        ? appLocalizationsOf(context).validationInvalid
                        : null,
                    onChanged: (s) {
                      _feeControl.value = s;
                      _feeControl.markAsDirty();
                      setState(() {});
                      widget.onChangeLicenseFee();
                    },
                  ),
                );
                final currency = LabeledInput(
                  labelText: appLocalizationsOf(context).currency,
                  child: ReactiveArDriveSelectField(
                    formControlName: 'licenseFeeCurrency',
                    showErrors: (control) => control.dirty && control.invalid,
                    validationMessages:
                        kValidationMessages(appLocalizationsOf(context)),
                    choices: [
                      for (final entry in udlCurrencyLabels.entries)
                        ArDriveChoice(value: entry.key, label: entry.value),
                    ],
                  ),
                );

                // Side by side leaves the fee a sliver on a phone: stack them.
                if (constraints.maxWidth < _kStackBelowWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      fee,
                      const SizedBox(height: ArDriveSpacing.md),
                      currency,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: fee),
                    const SizedBox(width: ArDriveSpacing.md),
                    Expanded(child: currency),
                  ],
                );
              },
            ),
            LabeledInput(
              labelText: appLocalizationsOf(context).commercialUseLabel,
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
              labelText: appLocalizationsOf(context).derivationsLabel,
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
                (element) =>
                    [const SizedBox(height: ArDriveSpacing.md), element],
              )
              // Gaps between the fields only: one after the last doubled the
              // gap to whatever follows the form.
              .skip(1)
              .toList(),
        ));
  }
}

import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/material.dart';

class PaymentMethodSelector extends StatelessWidget {
  final UploadMethod uploadMethod;
  final UploadCostEstimate? costEstimateTurbo;
  final UploadCostEstimate costEstimateAr;
  final bool hasNoTurboBalance;
  final bool isTurboUploadPossible;
  final String arBalance;
  final String turboCredits;
  final void Function() onTurboTopupSucess;
  final void Function() onArSelect;
  final void Function() onTurboSelect;

  const PaymentMethodSelector({
    super.key,
    required this.uploadMethod,
    required this.costEstimateTurbo,
    required this.costEstimateAr,
    required this.hasNoTurboBalance,
    required this.isTurboUploadPossible,
    required this.arBalance,
    required this.turboCredits,
    required this.onTurboTopupSucess,
    required this.onArSelect,
    required this.onTurboSelect,
  });

  @override
  Widget build(context) {
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      children: [
        Text(
          'Payment method:', // TODO: localize
          style: ArDriveTypography.body.buttonLargeBold(),
        ),
        const SizedBox(
          height: 8,
        ),
        ArDriveRadioButtonGroup(
          size: 15,
          onChanged: (index, value) {
            switch (index) {
              case 0:
                if (value) {
                  onArSelect();
                }
                break;

              case 1:
                if (value) {
                  onTurboSelect();
                }
                break;
            }
          },
          options: [
            // FIXME: rename to RadioButtonOption
            RadioButtonOptions(
              value: uploadMethod == UploadMethod.ar,
              // TODO: Localization
              text: 'Cost: ${winstonToAr(costEstimateAr.totalCost)} AR',
              textStyle: ArDriveTypography.body.buttonLargeBold(),
            ),
            if (costEstimateTurbo != null && isTurboUploadPossible)
              RadioButtonOptions(
                value: uploadMethod == UploadMethod.turbo,
                // TODO: Localization
                text: hasNoTurboBalance
                    ? ''
                    : 'Cost: ${winstonToAr(costEstimateTurbo!.totalCost)} Credits',
                textStyle: ArDriveTypography.body.buttonLargeBold(),
                content: hasNoTurboBalance
                    ? GestureDetector(
                        onTap: () {
                          showTurboTopupModal(context, onSuccess: () {
                            onTurboTopupSucess();
                          });
                        },
                        child: ArDriveClickArea(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                // TODO: use text with multiple styles
                                TextSpan(
                                  text: 'Use Turbo Credits', // TODO: localize
                                  style: ArDriveTypography.body
                                      .buttonLargeBold(
                                        color: ArDriveTheme.of(context)
                                            .themeData
                                            .colors
                                            .themeFgDefault,
                                      )
                                      .copyWith(
                                        decoration: TextDecoration.underline,
                                      ),
                                ),
                                TextSpan(
                                  text:
                                      ' for faster uploads.', // TODO: localize
                                  style: ArDriveTypography.body.buttonLargeBold(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgDefault,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : null,
              )
          ],
          builder: (index, radioButton) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              radioButton,
              Padding(
                padding: const EdgeInsets.only(left: 24.0),
                child: Text(
                  index == 0
                      // TODO: localize
                      ? 'Wallet Balance: $arBalance AR'
                      : 'Turbo Balance: $turboCredits Credits',
                  style: ArDriveTypography.body.buttonNormalBold(
                    color:
                        ArDriveTheme.of(context).themeData.colors.themeFgMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

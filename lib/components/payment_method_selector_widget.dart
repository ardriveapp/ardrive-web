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
  final bool sufficientArBalance;
  final String turboCredits;
  final bool sufficentCreditsBalance;
  final bool isFreeThanksToTurbo;
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
    required this.sufficientArBalance,
    required this.turboCredits,
    required this.sufficentCreditsBalance,
    required this.isFreeThanksToTurbo,
    required this.onTurboTopupSucess,
    required this.onArSelect,
    required this.onTurboSelect,
  });

  @override
  Widget build(context) {
    return Column(
      children: [
        if (!isFreeThanksToTurbo) ...[
          _buildContent(context),
          const SizedBox(height: 16),
          _getInsufficientBalanceMessage(context: context),
        ],
      ],
    );
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

  Widget _getInsufficientBalanceMessage({
    required BuildContext context,
  }) {
    if (uploadMethod == UploadMethod.turbo &&
        !sufficentCreditsBalance &&
        sufficientArBalance) {
      return GestureDetector(
        onTap: () {
          showTurboTopupModal(context, onSuccess: () {
            onTurboTopupSucess();
          });
        },
        child: ArDriveClickArea(
          child: Text.rich(
            TextSpan(
              text: 'Insufficient Credit balance for purchase. ',
              style: ArDriveTypography.body.captionBold(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
              ),
              children: [
                TextSpan(
                  text: 'Add Credits',
                  style: ArDriveTypography.body
                      .captionBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeErrorDefault,
                      )
                      .copyWith(decoration: TextDecoration.underline),
                ),
                TextSpan(
                  text: ' to use Turbo.',
                  style: ArDriveTypography.body.captionBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (uploadMethod == UploadMethod.ar && !sufficientArBalance) {
      return Text(
        'Insufficient AR balance for purchase.',
        style: ArDriveTypography.body.captionBold(
          color: ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
        ),
      );
    } else if (!sufficentCreditsBalance && !sufficientArBalance) {
      return GestureDetector(
        onTap: () {
          showTurboTopupModal(context, onSuccess: () {
            onTurboTopupSucess();
          });
        },
        child: ArDriveClickArea(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text:
                      'Insufficient balance to pay for this upload. You can either',
                  style: ArDriveTypography.body.captionBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  ),
                ),
                TextSpan(
                  text: ' add Turbo credits to your profile',
                  style: ArDriveTypography.body
                      .captionBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeErrorDefault,
                      )
                      .copyWith(
                        decoration: TextDecoration.underline,
                      ),
                ),
                TextSpan(
                  text: ' or use AR',
                  style: ArDriveTypography.body.captionBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const SizedBox();
  }
}

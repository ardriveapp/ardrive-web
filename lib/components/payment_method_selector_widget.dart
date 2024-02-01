import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/material.dart';

class PaymentMethodSelector extends StatelessWidget {
  final UploadPaymentMethodInfo uploadMethodInfo;
  final void Function() onTurboTopupSucess;
  final void Function() onArSelect;
  final void Function() onTurboSelect;

  const PaymentMethodSelector({
    super.key,
    required this.uploadMethodInfo,
    required this.onTurboTopupSucess,
    required this.onArSelect,
    required this.onTurboSelect,
  });

  @override
  Widget build(context) {
    return Column(
      children: [
        if (!uploadMethodInfo.isFreeThanksToTurbo) ...[
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
              value: uploadMethodInfo.uploadMethod == UploadMethod.ar,
              // TODO: Localization
              text:
                  'Cost: ${winstonToAr(uploadMethodInfo.costEstimateAr.totalCost)} AR',
              textStyle: ArDriveTypography.body.buttonLargeBold(),
            ),
            if (uploadMethodInfo.costEstimateTurbo != null &&
                uploadMethodInfo.isTurboUploadPossible)
              RadioButtonOptions(
                value: uploadMethodInfo.uploadMethod == UploadMethod.turbo,
                // TODO: Localization
                text: uploadMethodInfo.hasNoTurboBalance
                    ? ''
                    : 'Cost: ${winstonToAr(uploadMethodInfo.costEstimateTurbo!.totalCost)} Credits',
                textStyle: ArDriveTypography.body.buttonLargeBold(),
                content: uploadMethodInfo.hasNoTurboBalance
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
                      ? 'Wallet Balance: ${uploadMethodInfo.arBalance} AR'
                      : 'Turbo Balance: ${uploadMethodInfo.turboCredits} Credits',
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
    if (uploadMethodInfo.uploadMethod == UploadMethod.turbo &&
        !uploadMethodInfo.sufficentCreditsBalance &&
        uploadMethodInfo.sufficientArBalance) {
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
    } else if (uploadMethodInfo.uploadMethod == UploadMethod.ar &&
        !uploadMethodInfo.sufficientArBalance) {
      return Text(
        'Insufficient AR balance for purchase.',
        style: ArDriveTypography.body.captionBold(
          color: ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
        ),
      );
    } else if (!uploadMethodInfo.sufficentCreditsBalance &&
        !uploadMethodInfo.sufficientArBalance) {
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

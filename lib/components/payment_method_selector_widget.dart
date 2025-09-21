import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/material.dart';

class PaymentMethodSelector extends StatefulWidget {
  final UploadPaymentMethodInfo uploadMethodInfo;
  final void Function() onTurboTopupSucess;
  final void Function() onArSelect;
  final void Function() onTurboSelect;
  final bool useNewArDriveUI;
  final bool useDropdown;
  final bool showCongestionWarning;

  const PaymentMethodSelector({
    super.key,
    required this.uploadMethodInfo,
    required this.onTurboTopupSucess,
    required this.onArSelect,
    required this.onTurboSelect,
    this.useNewArDriveUI = false,
    this.useDropdown = false,
    this.showCongestionWarning = false,
  });

  @override
  State<PaymentMethodSelector> createState() => _PaymentMethodSelectorState();
}

class _PaymentMethodSelectorState extends State<PaymentMethodSelector> {
  late UploadMethod _selectedMethod;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.uploadMethodInfo.uploadMethod;
  }

  @override
  Widget build(context) {
    return Column(
      children: [
        if (widget.useDropdown) _buildDropdown(context),
        if (!widget.useDropdown) _buildContent(context),
        if (widget.showCongestionWarning && _selectedMethod == UploadMethod.ar)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: _buildCongestionWarning(context),
          ),
        _getInsufficientBalanceMessage(context: context),
      ],
    );
  }

  Widget _buildDropdown(BuildContext context) {
    return ArDriveDropdown(
      height: 45,
      maxHeight: 90,
      hasBorder: false,
      hasDivider: false,
      anchor: const Aligned(
        follower: Alignment.centerRight,
        target: Alignment.bottomRight,
        offset: Offset(0, 10),
      ),
      items: [
        _buildDropdownItem(context, UploadMethod.ar),
        _buildDropdownItem(context, UploadMethod.turbo),
      ],
      child: ArDriveClickArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCoinIcon(),
                  const SizedBox(width: 16),
                  Flexible(child: _buildSelectedItem(context)),
                ],
              ),
            ),
            ArDriveIcons.chevronDown(),
          ],
        ),
      ),
    );
  }

  ArDriveIcon _buildCoinIcon() {
    if (_selectedMethod == UploadMethod.ar) {
      return ArDriveIcons.arweaveCoin(
        size: 16,
      );
    } else {
      return ArDriveIcons.turboCoin(
        size: 16,
        color: ArDriveTheme.of(context).themeData.colorTokens.containerRed,
      );
    }
  }

  ArDriveDropdownItem _buildDropdownItem(
      BuildContext context, UploadMethod method) {
    final typography = ArDriveTypographyNew.of(context);

    String text;

    if (method == UploadMethod.ar) {
      text = 'Wallet Balance';
    } else {
      text = 'Turbo Balance';
    }

    return ArDriveDropdownItem(
      content: SizedBox(
        width: 164,
        height: 45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                text,
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
              if (_selectedMethod == method)
                ArDriveIcons.checkmark(
                  size: 16,
                )
            ],
          ),
        ),
      ),
      onClick: () {
        setState(() {
          _selectedMethod = method;
          if (method == UploadMethod.ar) {
            widget.onArSelect();
          } else {
            widget.onTurboSelect();
          }
        });
      },
    );
  }

  Widget _buildSelectedItem(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    if (_selectedMethod == UploadMethod.ar) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cost: ${winstonToAr(widget.uploadMethodInfo.costEstimateAr.totalCost)} AR',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          Text(
            'Payment Method: Wallet Balance: ${widget.uploadMethodInfo.arBalance} AR',
            style: typography.paragraphSmall(
              color: colorTokens.textLow,
            ),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cost: ${winstonToAr(widget.uploadMethodInfo.costEstimateTurbo!.totalCost)} Credits',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          Text(
            'Payment Method: Turbo Credits: ${widget.uploadMethodInfo.turboCredits} Credits',
            style: typography.paragraphSmall(
              color: colorTokens.textLow,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

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
                  widget.onArSelect();
                }
                break;

              case 1:
                if (value) {
                  widget.onTurboSelect();
                }
                break;
            }
          },
          options: [
            // FIXME: rename to RadioButtonOption
            RadioButtonOptions(
              value: widget.uploadMethodInfo.uploadMethod == UploadMethod.ar,
              // TODO: Localization
              text:
                  'Cost: ${winstonToAr(widget.uploadMethodInfo.costEstimateAr.totalCost)} AR',
              textStyle: widget.useNewArDriveUI
                  ? typography.paragraphLarge(
                      fontWeight: ArFontWeight.bold,
                    )
                  : ArDriveTypography.body.buttonLargeBold(),
            ),
            if (widget.uploadMethodInfo.costEstimateTurbo != null &&
                widget.uploadMethodInfo.isTurboUploadPossible)
              RadioButtonOptions(
                value:
                    widget.uploadMethodInfo.uploadMethod == UploadMethod.turbo,
                // TODO: Localization
                text: widget.uploadMethodInfo.hasNoTurboBalance
                    ? ''
                    : 'Cost: ${winstonToAr(widget.uploadMethodInfo.costEstimateTurbo!.totalCost)} Credits',
                textStyle: widget.useNewArDriveUI
                    ? typography.paragraphLarge(
                        color: colorTokens.textHigh,
                        fontWeight: ArFontWeight.bold)
                    : ArDriveTypography.body.buttonLargeBold(),
                content: widget.uploadMethodInfo.hasNoTurboBalance
                    ? GestureDetector(
                        onTap: () {
                          showTurboTopupModal(context, onSuccess: () {
                            widget.onTurboTopupSucess();
                          });
                        },
                        child: ArDriveClickArea(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                // TODO: use text with multiple styles
                                TextSpan(
                                  text: 'Use Turbo Credits', // TODO: localize
                                  style: widget.useNewArDriveUI
                                      ? typography.paragraphLarge(
                                          color: colorTokens.textMid,
                                          fontWeight: ArFontWeight.bold,
                                        )
                                      : ArDriveTypography.body.buttonLargeBold(
                                          color: ArDriveTheme.of(context)
                                              .themeData
                                              .colors
                                              .themeFgDefault,
                                        ),
                                ),
                                TextSpan(
                                  text:
                                      ' for faster uploads.', // TODO: localize
                                  style: widget.useNewArDriveUI
                                      ? typography.paragraphLarge(
                                          color: colorTokens.textMid,
                                          fontWeight: ArFontWeight.bold,
                                        )
                                      : ArDriveTypography.body.buttonLargeBold(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      index == 0
                          // TODO: localize
                          ? 'Wallet Balance: ${widget.uploadMethodInfo.arBalance} AR'
                          : 'Turbo Balance: ${widget.uploadMethodInfo.turboCredits} Credits',
                      style: widget.useNewArDriveUI
                          ? typography.paragraphNormal(
                              color: colorTokens.textLow,
                              fontWeight: ArFontWeight.semiBold,
                            )
                          : ArDriveTypography.body.buttonNormalBold(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgMuted,
                            ),
                    ),
                    if (index == 0 && widget.showCongestionWarning)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: _buildCongestionWarning(context),
                      ),
                  ],
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
    if (widget.uploadMethodInfo.uploadMethod == UploadMethod.turbo &&
        !widget.uploadMethodInfo.sufficentCreditsBalance &&
        widget.uploadMethodInfo.sufficientArBalance) {
      return GestureDetector(
        onTap: () {
          showTurboTopupModal(context, onSuccess: () {
            widget.onTurboTopupSucess();
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
    } else if (widget.uploadMethodInfo.uploadMethod == UploadMethod.ar &&
        !widget.uploadMethodInfo.sufficientArBalance) {
      return Text(
        'Insufficient AR balance for purchase.',
        style: ArDriveTypography.body.captionBold(
          color: ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
        ),
      );
    } else if (!widget.uploadMethodInfo.sufficentCreditsBalance &&
        !widget.uploadMethodInfo.sufficientArBalance) {
      return GestureDetector(
        onTap: () {
          showTurboTopupModal(context, onSuccess: () {
            widget.onTurboTopupSucess();
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

  Widget _buildCongestionWarning(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ArDriveTheme.of(context).themeData.colors.themeWarningSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ArDriveTheme.of(context).themeData.colors.themeWarningEmphasis,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: ArDriveTheme.of(context).themeData.colors.themeWarningEmphasis,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              appLocalizationsOf(context).congestionWarningShort,
              style: widget.useNewArDriveUI
                  ? typography.paragraphSmall(
                      color: ArDriveTheme.of(context).themeData.colors.themeWarningFg,
                      fontWeight: ArFontWeight.semiBold,
                    )
                  : ArDriveTypography.body.smallBold(
                      color: ArDriveTheme.of(context).themeData.colors.themeWarningFg,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
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

  /// Grants this account's derived Arweave wallet the right to spend credits
  /// held on the wallet the reader signed in with.
  ///
  /// Returns whether the grant went through. Optional, and null wherever the
  /// sheet has no way to sign: the notice then says where the credits are and
  /// leaves the reader to share them in Turbo, which is what it did before this
  /// control existed.
  final Future<bool> Function()? onShareCredits;
  final void Function() onArSelect;
  final void Function() onTurboSelect;
  final bool useNewArDriveUI;
  final bool useDropdown;
  final bool showCongestionWarning;

  const PaymentMethodSelector({
    super.key,
    required this.uploadMethodInfo,
    required this.onTurboTopupSucess,
    this.onShareCredits,
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
                // No top-up offer for somebody whose credits are on the wallet
                // they signed in with: offering to sell more to a person who has
                // just paid is the worst answer available, and it is the one this
                // sheet gave. The notice saying where the credits are is drawn
                // under the sheet by [_getInsufficientBalanceMessage] instead,
                // because that is the one place every mode renders - the dropdown
                // most uploads use has no radio row to put it in.
                content: widget.uploadMethodInfo.sourceWalletCredits != null
                    ? null
                    : widget.uploadMethodInfo.hasNoTurboBalance
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
                                      text:
                                          'Use Turbo Credits', // TODO: localize
                                      style: widget.useNewArDriveUI
                                          ? typography.paragraphLarge(
                                              color: colorTokens.textMid,
                                              fontWeight: ArFontWeight.bold,
                                            )
                                          : ArDriveTypography.body
                                              .buttonLargeBold(
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
                                          : ArDriveTypography.body
                                              .buttonLargeBold(
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
    final info = widget.uploadMethodInfo;
    final credits = info.sourceWalletCredits;

    // Where the credits are, in place of an offer to sell more. Drawn here
    // because this message is the one thing every mode renders: the radio row
    // used to carry it, and the dropdown the main upload sheet uses had no
    // radio row, so the reader this was built for never saw it.
    //
    // Only while the sheet is refusing, which is the same test the branches
    // below use. A reader who can pay with AR is not stuck, and a call to share
    // credits beside a working upload button is noise.
    if (credits != null) {
      final arShort =
          info.uploadMethod == UploadMethod.ar && !info.sufficientArBalance;
      final turboShort = info.uploadMethod == UploadMethod.turbo &&
          !info.sufficentCreditsBalance &&
          info.sufficientArBalance;
      final bothShort =
          !info.sufficentCreditsBalance && !info.sufficientArBalance;

      if (!arShort && !turboShort && !bothShort) {
        return const SizedBox();
      }

      final notice = _SourceWalletCreditsNotice(
        credits: credits,
        useNewArDriveUI: widget.useNewArDriveUI,
        onShare: widget.onShareCredits,
      );

      // Short of AR while paying with AR is still worth saying: it is true, and
      // it is not a sales pitch. The notice beside it is the way out.
      if (arShort) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Insufficient AR balance for purchase.',
              style: ArDriveTypography.body.captionBold(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
              ),
            ),
            const SizedBox(height: 8),
            notice,
          ],
        );
      }

      return notice;
    }

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
            color:
                ArDriveTheme.of(context).themeData.colors.themeWarningEmphasis,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              appLocalizationsOf(context).congestionWarningShort,
              style: widget.useNewArDriveUI
                  ? typography.paragraphSmall(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeWarningFg,
                      fontWeight: ArFontWeight.semiBold,
                    )
                  : ArDriveTypography.body.smallBold(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeWarningFg,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says where the credits are, instead of offering to sell more.
///
/// Shown when the wallet somebody signed in with holds Turbo credits that this
/// upload cannot spend. Signing in with Phantom or MetaMask derives a
/// deterministic Arweave wallet, and that derived address is what ArDrive bills;
/// credits bought in Turbo's own console land on the sign-in wallet's own
/// account instead. Both balances are real and neither system used to mention
/// the other.
///
/// It names both addresses rather than explaining the derivation. Somebody who
/// has just been refused an upload wants to know where their money is, and the
/// account menu already explains how the two wallets relate.
class _SourceWalletCreditsNotice extends StatefulWidget {
  const _SourceWalletCreditsNotice({
    required this.credits,
    required this.useNewArDriveUI,
    this.onShare,
  });

  final SourceWalletCredits credits;
  final bool useNewArDriveUI;

  /// See [PaymentMethodSelector.onShareCredits].
  final Future<bool> Function()? onShare;

  @override
  State<_SourceWalletCreditsNotice> createState() =>
      _SourceWalletCreditsNoticeState();
}

class _SourceWalletCreditsNoticeState
    extends State<_SourceWalletCreditsNotice> {
  bool _sharing = false;
  bool _failed = false;

  Future<void> _share() async {
    final onShare = widget.onShare;

    if (onShare == null || _sharing) {
      return;
    }

    setState(() {
      _sharing = true;
      _failed = false;
    });

    // Never throws out of here. A wallet extension that is gone, or a reader
    // who declines the prompt, leaves the sheet exactly as it was with the
    // instructions still on it - which is a worse outcome than one press, and a
    // much better one than a dead end.
    var shared = false;

    try {
      shared = await onShare();
    } catch (_) {
      shared = false;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _sharing = false;
      _failed = !shared;
    });
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final chain = switch (widget.credits.walletType) {
      WalletType.ethereum => 'Ethereum',
      WalletType.solana => 'Solana',
      WalletType.arweave => 'Arweave',
    };

    final muted = widget.useNewArDriveUI
        ? typography.paragraphNormal(color: colorTokens.textMid)
        : ArDriveTypography.body.captionRegular();

    // With no way to sign, the sheet says where the money is and stops. Also
    // where a failed attempt lands, because the instruction is still true.
    final canShare = widget.onShare != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${winstonToAr(widget.credits.balance)} Credits are on your $chain '
          'wallet ${truncateString(widget.credits.sourceAddress, offsetStart: 6, offsetEnd: 4)}.',
          style: widget.useNewArDriveUI
              ? typography.paragraphNormal(
                  color: colorTokens.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                )
              : ArDriveTypography.body.captionBold(),
        ),
        const SizedBox(height: 2),
        Text(
          canShare && !_failed
              ? 'Uploads are paid from your Arweave address. Share the credits '
                  'across to use them here.'
              : 'Uploads are paid from your Arweave address. Share the credits '
                  'to it in Turbo to use them here.',
          style: muted,
        ),
        // Whole, and copyable, wherever the reader may have to do this by hand.
        // A shortened address cannot be pasted into Turbo.
        if (!canShare || _failed) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(widget.credits.arweaveAddress, style: muted),
              ),
              CopyButton(text: widget.credits.arweaveAddress, size: 16),
            ],
          ),
        ],
        if (_failed) ...[
          const SizedBox(height: 2),
          // Just the fact. The retry is the button below and the manual route
          // is the address above; saying either again here only repeats what is
          // already on screen.
          Text(
            'That did not go through.',
            style: widget.useNewArDriveUI
                ? typography.paragraphNormal(color: colorTokens.textRed)
                : ArDriveTypography.body.captionRegular(),
          ),
        ],
        if (canShare) ...[
          const SizedBox(height: 8),
          ArDriveButtonNew(
            text: _sharing ? 'Sharing...' : 'Share credits',
            typography: typography,
            variant: ButtonVariant.primary,
            maxHeight: 36,
            isDisabled: _sharing,
            onPressed: _share,
          ),
        ],
      ],
    );
  }
}

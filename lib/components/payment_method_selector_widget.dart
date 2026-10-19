import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/components/inline_warning.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
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

  /// Shows the two ways to pay as option cards, each with its cost and
  /// balance, in place of the older radio list.
  final bool useOptionCards;
  final bool showCongestionWarning;

  const PaymentMethodSelector({
    super.key,
    required this.uploadMethodInfo,
    required this.onTurboTopupSucess,
    this.onShareCredits,
    required this.onArSelect,
    required this.onTurboSelect,
    this.useNewArDriveUI = false,
    this.useOptionCards = false,
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
        if (widget.useOptionCards) _buildOptionCards(context),
        if (!widget.useOptionCards) _buildContent(context),
        if (widget.showCongestionWarning && _selectedMethod == UploadMethod.ar)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: _buildCongestionWarning(context),
          ),
        // The bloc's method, not [_selectedMethod]: the radio buttons change
        // only the bloc's. Not while the wallet can't pay: there is no upload
        // to keep the tab open for.
        if (widget.uploadMethodInfo.uploadMethod == UploadMethod.ar &&
            widget.uploadMethodInfo.sufficientArBalance)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: InlineWarning(
              text: appLocalizationsOf(context).uploadWithWalletKeepTabOpen,
              useNewArDriveUI: widget.useNewArDriveUI,
            ),
          ),
        _getInsufficientBalanceMessage(context: context),
      ],
    );
  }

  /// Both ways to pay, side by side with what each costs and what is left,
  /// in the option cards the Turbo top-up uses to choose how to pay.
  Widget _buildOptionCards(BuildContext context) {
    final info = widget.uploadMethodInfo;
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);
    final l10n = appLocalizationsOf(context);
    final turboPossible =
        info.costEstimateTurbo != null && info.isTurboUploadPossible;

    void select(UploadMethod method) {
      setState(() => _selectedMethod = method);
      method == UploadMethod.ar ? widget.onArSelect() : widget.onTurboSelect();
    }

    final String turboBalance;
    if (info.hasNoTurboBalance) {
      turboBalance = l10n.noCreditsYet;
    } else if (info.sufficentCreditsBalance) {
      turboBalance = l10n.creditsAvailable(info.turboCredits);
    } else {
      turboBalance = l10n.notEnoughCredits(info.turboCredits);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.paymentMethod,
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.themeFgMuted,
          ),
        ),
        const SizedBox(height: 8),
        // One bordered group, a row per way to pay: the same choice as two
        // separate cards, in about two thirds of the height.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.themeBorderDefault),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (turboPossible) ...[
                _PaymentOptionCard(
                  title: l10n.paymentOptionTurboCredits,
                  balance: turboBalance,
                  isShort: !info.sufficentCreditsBalance,
                  cost: l10n.amountInCredits(convertWinstonToCostString(
                      info.costEstimateTurbo!.totalCost)),
                  isSelected: _selectedMethod == UploadMethod.turbo,
                  onTap: () => select(UploadMethod.turbo),
                ),
                Divider(height: 1, color: colors.themeBorderDefault),
              ],
              _PaymentOptionCard(
                title: l10n.paymentOptionWallet,
                balance: info.sufficientArBalance
                    ? l10n.arAvailable(info.arBalance)
                    : l10n.notEnoughAr(info.arBalance),
                isShort: !info.sufficientArBalance,
                cost: l10n.amountInAr(
                    convertWinstonToCostString(info.costEstimateAr.totalCost)),
                isSelected: _selectedMethod == UploadMethod.ar,
                onTap: () => select(UploadMethod.ar),
              ),
            ],
          ),
        ),
      ],
    );
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
              text: appLocalizationsOf(context).cost(convertWinstonToCostString(
                  widget.uploadMethodInfo.costEstimateAr.totalCost)),
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
                text: widget.uploadMethodInfo.hasNoTurboBalance
                    ? ''
                    : appLocalizationsOf(context).costCredits(
                        convertWinstonToCostString(widget
                            .uploadMethodInfo.costEstimateTurbo!.totalCost)),
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
                          : 'Turbo Balance: ${widget.uploadMethodInfo.turboCredits} credits',
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
      // it is not a sales pitch. The notice beside it is the way out. The
      // option cards already say it on the wallet card.
      if (arShort && !widget.useOptionCards) {
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

    final bothShort = !widget.uploadMethodInfo.sufficentCreditsBalance &&
        !widget.uploadMethodInfo.sufficientArBalance;

    if (widget.uploadMethodInfo.uploadMethod == UploadMethod.turbo &&
        !widget.uploadMethodInfo.sufficentCreditsBalance &&
        widget.uploadMethodInfo.sufficientArBalance) {
      // The Turbo card already says the credits are short; what is left to
      // offer is the way to add some.
      if (widget.useOptionCards) {
        return GestureDetector(
          onTap: () {
            showTurboTopupModal(context, onSuccess: () {
              widget.onTurboTopupSucess();
            });
          },
          child: ArDriveClickArea(
            child: Text(
              appLocalizationsOf(context).addCreditsToUpload,
              style: ArDriveTypography.body
                  .captionBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  )
                  .copyWith(decoration: TextDecoration.underline),
            ),
          ),
        );
      }
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
    }

    // With the option cards, the wallet card already says AR is short. When
    // the credits are short too, the message below still has to say so,
    // because it carries the only way forward: adding credits.
    if (widget.uploadMethodInfo.uploadMethod == UploadMethod.ar &&
        !widget.uploadMethodInfo.sufficientArBalance &&
        !(widget.useOptionCards && bothShort)) {
      if (widget.useOptionCards) {
        return const SizedBox();
      }
      return Text(
        'Insufficient AR balance for purchase.',
        style: ArDriveTypography.body.captionBold(
          color: ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
        ),
      );
    }

    if (bothShort) {
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
                  text: '${appLocalizationsOf(context).notEnoughCreditsOrAr} ',
                  style: ArDriveTypography.body.captionBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  ),
                ),
                TextSpan(
                  text: appLocalizationsOf(context).addCreditsToUpload,
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
              ],
            ),
          ),
        ),
      );
    }
    return const SizedBox();
  }

  Widget _buildCongestionWarning(BuildContext context) {
    return InlineWarning(
      text: appLocalizationsOf(context).congestionWarningShort,
      useNewArDriveUI: widget.useNewArDriveUI,
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
          '${convertWinstonToLiteralString(widget.credits.balance)} credits are on your $chain '
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

/// One way to pay, a row in the group: a radio dot, the method, what is left,
/// and on the right what this upload costs with it.
class _PaymentOptionCard extends StatelessWidget {
  const _PaymentOptionCard({
    required this.title,
    required this.balance,
    required this.isShort,
    required this.cost,
    required this.isSelected,
    required this.onTap,
  });

  final String title;

  /// What is left to pay with, or that it is not enough.
  final String balance;

  /// Whether [balance] is too little for this upload. Drawn as an error only on
  /// the selected card, where it is what stops the upload; on the other card it
  /// is just information.
  final bool isShort;
  final String cost;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: isSelected,
      // The chosen row is lifted to the surface colour; the other stays the
      // dialog's own.
      child: Material(
        color: isSelected ? colors.themeBgSurface : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? colors.themeFgDefault
                          : colors.themeBorderDefault,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.themeFgDefault,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: colors.themeFgDefault,
                        ),
                      ),
                      Text(
                        balance,
                        style: typography.paragraphSmall(
                          color: isShort && isSelected
                              ? colors.themeErrorDefault
                              : colors.themeFgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  cost,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.bold,
                    color: colors.themeFgDefault,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

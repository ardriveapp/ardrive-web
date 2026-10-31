import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/components/copy_button.dart';
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

  final bool showCongestionWarning;

  /// Whether to say what is short and how to add credits under the choice.
  /// The upload review says that itself, above the choice.
  final bool showBalanceMessages;

  const PaymentMethodSelector({
    super.key,
    required this.uploadMethodInfo,
    required this.onTurboTopupSucess,
    this.onShareCredits,
    required this.onArSelect,
    required this.onTurboSelect,
    this.showCongestionWarning = false,
    this.showBalanceMessages = true,
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
        _buildOptionCards(context),
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
            child: SizedBox(
              width: double.infinity,
              child: ArDriveNotice(
                type: ArDriveNoticeType.warning,
                message:
                    appLocalizationsOf(context).uploadWithWalletKeepTabOpen,
              ),
            ),
          ),
        if (widget.showBalanceMessages)
          _getInsufficientBalanceMessage(context: context),
      ],
    );
  }

  /// Both ways to pay, side by side with what each costs and what is left,
  /// in the option cards the Turbo top-up uses to choose how to pay.
  Widget _buildOptionCards(BuildContext context) {
    final info = widget.uploadMethodInfo;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
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
            color: colorTokens.textMid,
          ),
        ),
        const SizedBox(height: ArDriveSpacing.xs),
        // One bordered group, a row per way to pay: the same choice as two
        // separate cards, in about two thirds of the height.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ArDriveRadius.lg),
            border: Border.all(color: colorTokens.strokeMid),
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
                Divider(height: 1, color: colorTokens.strokeMid),
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

      final notice = SourceWalletCreditsNotice(
        credits: credits,
        onShare: widget.onShareCredits,
      );

      // Short of AR is already said on the wallet card; the notice is the way
      // out. While the credits there would cover it once shared, it is the
      // only one: no offer to buy more beside it.
      final cost = info.costEstimateTurbo?.totalCost;
      final shortEvenShared = !info.turboUnreachable &&
          cost != null &&
          info.turboBalance + credits.balance < cost;

      if (!shortEvenShared) {
        return notice;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          notice,
          _addCreditsLink(context),
        ],
      );
    }

    final bothShort = !widget.uploadMethodInfo.sufficentCreditsBalance &&
        !widget.uploadMethodInfo.sufficientArBalance;

    if (widget.uploadMethodInfo.uploadMethod == UploadMethod.turbo &&
        !widget.uploadMethodInfo.sufficentCreditsBalance &&
        widget.uploadMethodInfo.sufficientArBalance) {
      // The Turbo card already says the credits are short; what is left to
      // offer is the way to add some.
      return _addCreditsLink(context);
    }

    // The wallet card already says AR is short. When the credits are short
    // too, the message below still has to say so, because it carries the only
    // way forward: adding credits.
    if (widget.uploadMethodInfo.uploadMethod == UploadMethod.ar &&
        !widget.uploadMethodInfo.sufficientArBalance &&
        !bothShort) {
      return const SizedBox();
    }

    if (bothShort) {
      return Padding(
        padding: const EdgeInsets.only(top: ArDriveSpacing.sm),
        child: SizedBox(
          width: double.infinity,
          child: ArDriveNotice(
            type: ArDriveNoticeType.error,
            message: appLocalizationsOf(context).notEnoughCreditsOrAr,
            actionLabel: appLocalizationsOf(context).uploadAddCredits,
            onAction: () => showTurboTopupModal(
              context,
              onSuccess: widget.onTurboTopupSucess,
            ),
          ),
        ),
      );
    }
    return const SizedBox();
  }

  /// Opens the Turbo top-up; on success the sheet reads its balance again.
  Widget _addCreditsLink(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: ArDriveSpacing.sm),
          child: ArDriveLink(
            text: appLocalizationsOf(context).uploadAddCredits,
            isAction: true,
            onTap: () => showTurboTopupModal(
              context,
              onSuccess: widget.onTurboTopupSucess,
            ),
          ),
        ),
      );

  Widget _buildCongestionWarning(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ArDriveNotice(
        type: ArDriveNoticeType.warning,
        message: appLocalizationsOf(context).congestionWarningShort,
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
class SourceWalletCreditsNotice extends StatefulWidget {
  const SourceWalletCreditsNotice({
    super.key,
    required this.credits,
    this.onShare,
  });

  final SourceWalletCredits credits;

  /// See [PaymentMethodSelector.onShareCredits].
  final Future<bool> Function()? onShare;

  @override
  State<SourceWalletCreditsNotice> createState() =>
      _SourceWalletCreditsNoticeState();
}

class _SourceWalletCreditsNoticeState extends State<SourceWalletCreditsNotice> {
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

    final muted = typography.paragraphNormal(color: colorTokens.textMid);

    // With no way to sign, the sheet says where the money is and stops. Also
    // where a failed attempt lands, because the instruction is still true.
    final canShare = widget.onShare != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: typography.paragraphNormal(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.semiBold,
            ),
            children: ArDriveIdText.spansIn(
              '${convertWinstonToLiteralString(widget.credits.balance)} credits are on your $chain '
              'wallet ${shortenId(widget.credits.sourceAddress)}.',
              shortenId(widget.credits.sourceAddress),
              idStyle: typography.code(color: colorTokens.textHigh),
            ),
          ),
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
                child: Text(widget.credits.arweaveAddress,
                    style: typography.code(color: colorTokens.textMid)),
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
            style: typography.paragraphNormal(color: colorTokens.statusErrorFg),
          ),
        ],
        if (canShare) ...[
          const SizedBox(height: 8),
          ArDriveButtonNew(
            text: _sharing ? 'Sharing...' : 'Share credits',
            typography: typography,
            variant: ButtonVariant.primary,
            size: ArDriveButtonSize.compact,
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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: isSelected,
      // The chosen row is tinted a shade off the dialog, in either theme and
      // on any dialog colour; the other stays the dialog's own.
      child: Material(
        color: isSelected
            ? colorTokens.buttonSecondaryDefault
            : Colors.transparent,
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
                      // A control's edge must stand out from the row (3:1);
                      // strokeHigh is a divider and nearly vanishes here.
                      color: isSelected
                          ? colorTokens.textHigh
                          : colorTokens.textLow,
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
                              color: colorTokens.textHigh,
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
                          color: colorTokens.textHigh,
                        ),
                      ),
                      Text(
                        balance,
                        style: typography.paragraphSmall(
                          color: isShort && isSelected
                              ? colorTokens.statusErrorFg
                              : colorTokens.textMid,
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
                    color: colorTokens.textHigh,
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

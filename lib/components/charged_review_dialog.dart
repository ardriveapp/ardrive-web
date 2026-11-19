import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/components/turbo_credits_funding.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What a review that already knows its costs says about paying: the costs a
/// cubit read, in the terms [UploadReviewSummary] decides from.
///
/// The snapshot dialogs price their own upload, so they hand the numbers over
/// and the review is the upload's: free, or Turbo Credits, or the wallet when
/// the person picks it.
UploadPaymentMethodInfo chargedReviewPaymentInfo({
  required UploadMethod method,
  required bool arChosen,
  required int totalSize,
  required UploadCostEstimate costEstimateAr,
  required UploadCostEstimate? costEstimateTurbo,
  required BigInt turboBalance,
  required String turboCredits,
  required String arBalance,
  required bool sufficientArBalance,
  required FreeUploadStatus freeStatus,
  bool turboUnreachable = false,
  SourceWalletCredits? sourceWalletCredits,
}) {
  // A zero estimate is the placeholder for a price Turbo did not give.
  final hasTurboPrice =
      (costEstimateTurbo?.totalCost ?? BigInt.zero) > BigInt.zero;
  return UploadPaymentMethodInfo(
    uploadMethod: method,
    costEstimateTurbo: costEstimateTurbo,
    costEstimateAr: costEstimateAr,
    hasNoTurboBalance: turboBalance == BigInt.zero,
    isTurboUploadPossible: hasTurboPrice,
    arBalance: arBalance,
    sufficientArBalance: sufficientArBalance,
    turboCredits: turboCredits,
    sufficentCreditsBalance:
        hasTurboPrice && turboBalance >= costEstimateTurbo!.totalCost,
    freeStatus: freeStatus,
    totalSize: totalSize,
    turboBalanceWinc: turboBalance,
    turboUnreachable: turboUnreachable,
    sourceWalletCredits: sourceWalletCredits,
    arChosen: arChosen,
  );
}

/// The upload review, for something whose cost is read elsewhere: a snapshot.
///
/// It keeps what the shared review needs from the page that shows it: that
/// the wallet is only used when picked, and that Add credits and Try again
/// read the balance again, with no cost shown until it is back.
class ChargedReviewDialog extends StatefulWidget {
  const ChargedReviewDialog({
    super.key,
    required this.title,
    required this.destination,
    required this.primaryLabel,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
    required this.refresh,
    required this.onMethodChanged,
    required this.method,
    required this.totalSize,
    required this.costEstimateAr,
    required this.costEstimateTurbo,
    required this.turboBalance,
    required this.turboCredits,
    required this.arBalance,
    required this.sufficientArBalance,
    required this.freeStatus,
    required this.files,
    this.turboUnreachable = false,
    this.leading = const [],
    this.extras = const [],
    this.lookUpSourceCredits,
    this.creditSharing,
  });

  final String title;
  final String destination;
  final String primaryLabel;

  /// Confirm was pressed and has not come back: the primary spins, Cancel
  /// waits.
  final bool busy;

  /// Pays the way the review showed.
  final void Function(UploadMethod method) onConfirm;
  final VoidCallback onCancel;

  /// Reads the Turbo Credits balance (and price) again.
  final Future<void> Function() refresh;

  /// The person picked how to pay.
  final void Function(UploadMethod method) onMethodChanged;

  final UploadMethod method;
  final int totalSize;
  final UploadCostEstimate costEstimateAr;
  final UploadCostEstimate? costEstimateTurbo;
  final BigInt turboBalance;

  /// The balances as the payment choice shows them.
  final String turboCredits;
  final String arBalance;
  final bool sufficientArBalance;
  final FreeUploadStatus freeStatus;

  /// What is uploaded, as rows: the name and the size.
  final List<UploadReviewFile> files;

  /// The balance could not be read: no cost to pay on, only Try again.
  final bool turboUnreachable;

  final List<Widget> leading;
  final List<Widget> extras;

  /// Credits on the sign-in wallet, when credits are short. The app's own
  /// lookup when null.
  final Future<SourceWalletCredits?> Function(BuildContext context)?
      lookUpSourceCredits;

  /// Shares those credits to this account. The app's own when null.
  final CreditSharingService? creditSharing;

  @override
  State<ChargedReviewDialog> createState() => _ChargedReviewDialogState();
}

class _ChargedReviewDialogState extends State<ChargedReviewDialog> {
  /// The wallet is the way to pay only once the person picks it.
  var _arChosen = false;

  /// The balance is being read again: no cost until it is back.
  var _reading = false;

  /// Credits found on the sign-in wallet, asked once, and only when credits
  /// are short: everyone else pays for none of it.
  SourceWalletCredits? _sourceCredits;
  var _lookedUp = false;

  CreditSharingService get _sharing =>
      widget.creditSharing ??
      CreditSharingService.fromConfig(context.read<ConfigService>());

  bool get _canShare =>
      _sourceCredits?.walletType == WalletType.solana && _sharing.isSupported;

  Future<SourceWalletCredits?> _findSourceCredits(BuildContext context) async {
    final user = context.read<ArDriveAuth>().currentUser;
    final address = user.sourceWalletAddress;
    final type = walletTypeOfSourceAddress(address);
    if (address == null || type == null) return null;
    final balance = await context
        .read<PaymentService>()
        .getBalanceForAddress(address: address, walletType: type);
    if (balance <= BigInt.zero) return null;
    return SourceWalletCredits(
      balance: balance,
      sourceAddress: address,
      walletType: type,
      arweaveAddress: user.walletAddress,
    );
  }

  Future<void> _lookUp() async {
    try {
      final found = await (widget.lookUpSourceCredits ?? _findSourceCredits)(
          context);
      if (mounted && found != null) setState(() => _sourceCredits = found);
    } catch (e) {
      logger.d('Could not check the sign-in wallet for credits: $e');
    }
  }

  Future<bool> _share() async {
    final credits = _sourceCredits;
    if (credits == null || !_canShare) return false;
    try {
      await _sharing.shareCreditsFromSignInWallet(
        sourceAddress: credits.sourceAddress,
        approvedAddress: credits.arweaveAddress,
        approvedWinc: credits.balance,
      );
    } catch (e) {
      logger.i('Sharing credits from the sign-in wallet did not go through: $e');
      return false;
    }
    if (!mounted) return true;
    // The grant moves those credits into the balance Turbo reports, so they
    // are no longer extra: read the balance again without them.
    setState(() => _sourceCredits = null);
    _refresh();
    return true;
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _reading = true);
    try {
      await widget.refresh();
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  UploadPaymentMethodInfo get _info => chargedReviewPaymentInfo(
        method: widget.method,
        arChosen: _arChosen,
        totalSize: widget.totalSize,
        costEstimateAr: widget.costEstimateAr,
        costEstimateTurbo: widget.costEstimateTurbo,
        turboBalance: widget.turboBalance,
        turboCredits: widget.turboCredits,
        arBalance: widget.arBalance,
        sufficientArBalance: widget.sufficientArBalance,
        freeStatus: widget.freeStatus,
        turboUnreachable: widget.turboUnreachable,
        sourceWalletCredits: _sourceCredits,
      );

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final summary = _reading ? null : UploadReviewSummary.fromPaymentInfo(info);
    final legacy = summary?.usesLegacySelector ?? false;
    if (summary != null && summary.needsCredits && !_lookedUp) {
      _lookedUp = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lookUp();
      });
    }
    // Shown as the review reads it: Turbo Credits until the wallet is picked.
    final shown = legacy
        ? info
        : info.copyWith(
            uploadMethod: _arChosen ? UploadMethod.ar : UploadMethod.turbo,
          );

    return UploadReviewDialog(
      title: widget.title,
      destination: widget.destination,
      files: widget.files,
      leading: widget.leading,
      extras: widget.extras,
      summary: summary,
      primaryLabel: widget.primaryLabel,
      primaryBusy: widget.busy,
      onUpload: (method) {
        widget.onMethodChanged(method);
        widget.onConfirm(method);
      },
      onCancel: widget.onCancel,
      funding: TurboCreditsFunding(context, onRefresh: _refresh),
      canShareInApp: _canShare,
      sourceWalletNotice: _sourceCredits == null
          ? null
          : SourceWalletCreditsNotice(
              credits: _sourceCredits!,
              onShare: _canShare ? _share : null,
            ),
      paymentChoice: PaymentMethodSelector(
        key: ValueKey(shown.uploadMethod),
        uploadMethodInfo: shown,
        showBalanceMessages: legacy,
        onTurboTopupSucess: _refresh,
        onArSelect: () {
          setState(() => _arChosen = true);
          widget.onMethodChanged(UploadMethod.ar);
        },
        onTurboSelect: () {
          setState(() => _arChosen = false);
          widget.onMethodChanged(UploadMethod.turbo);
        },
      ),
    );
  }
}

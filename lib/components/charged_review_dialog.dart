import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/components/turbo_credits_funding.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:flutter/material.dart';

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
    this.leading = const [],
    this.extras = const [],
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

  final List<Widget> leading;
  final List<Widget> extras;

  @override
  State<ChargedReviewDialog> createState() => _ChargedReviewDialogState();
}

class _ChargedReviewDialogState extends State<ChargedReviewDialog> {
  /// The wallet is the way to pay only once the person picks it.
  var _arChosen = false;

  /// The balance is being read again: no cost until it is back.
  var _reading = false;

  Future<void> _refresh() async {
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
      );

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final summary = _reading ? null : UploadReviewSummary.fromPaymentInfo(info);
    final legacy = summary?.usesLegacySelector ?? false;
    // Shown as the review reads it: Turbo Credits until the wallet is picked.
    final shown = legacy
        ? info
        : info.copyWith(
            uploadMethod: _arChosen ? UploadMethod.ar : UploadMethod.turbo,
          );

    return UploadReviewDialog(
      title: widget.title,
      destination: widget.destination,
      files: const [],
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

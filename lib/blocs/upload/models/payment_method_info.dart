import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:equatable/equatable.dart';

class UploadPaymentMethodInfo extends Equatable {
  final UploadMethod uploadMethod;
  final UploadCostEstimate? costEstimateTurbo;
  final UploadCostEstimate costEstimateAr;
  final bool hasNoTurboBalance;
  final bool isTurboUploadPossible;
  final String arBalance;
  final bool sufficientArBalance;
  final String turboCredits;
  final bool sufficentCreditsBalance;

  /// Whether this upload is free, and if not, why not.
  final FreeUploadStatus freeStatus;
  final UploadPlan? uploadPlanForAR;
  final UploadPlan? uploadPlanForTurbo;
  final int totalSize;
  final List<String>? paidBy;

  /// Credits sitting on the wallet this user signed in with, when there are
  /// any and this upload cannot be paid for.
  ///
  /// Null means there is nothing to say, and covers three different cases on
  /// purpose: the account was never asked (no sign-in wallet, or the balance
  /// was sufficient), it was asked and holds nothing, or the question could not
  /// be answered. Only a confirmed non-zero balance is worth interrupting
  /// somebody with. See [SourceWalletCredits].
  final SourceWalletCredits? sourceWalletCredits;

  /// The Turbo Credits this wallet can spend, in winston credits, when known.
  /// [turboCredits] is the same amount as text. See [turboBalance].
  final BigInt? turboBalanceWinc;

  /// [turboBalanceWinc], or zero.
  BigInt get turboBalance => turboBalanceWinc ?? BigInt.zero;

  /// Turbo's price for this upload, or the balance, could not be read, so
  /// [costEstimateTurbo] and [turboBalance] are placeholders that must not be
  /// shown or compared. See [UploadPaymentInfo.turboUnreachable].
  final bool turboUnreachable;

  /// The person picked the wallet themselves. The wallet is never chosen for
  /// them: a default of AR, as preparation picks when credits are short or
  /// Turbo can't be reached, is not a choice.
  final bool arChosen;

  const UploadPaymentMethodInfo({
    required this.uploadMethod,
    required this.costEstimateTurbo,
    required this.costEstimateAr,
    required this.hasNoTurboBalance,
    required this.isTurboUploadPossible,
    required this.arBalance,
    required this.sufficientArBalance,
    required this.turboCredits,
    required this.sufficentCreditsBalance,
    required this.freeStatus,
    this.uploadPlanForAR,
    this.uploadPlanForTurbo,
    required this.totalSize,
    this.paidBy,
    this.sourceWalletCredits,
    this.turboBalanceWinc,
    this.turboUnreachable = false,
    this.arChosen = false,
  });

  bool get isFreeThanksToTurbo => freeStatus == FreeUploadStatus.free;

  /// Would have been free on size, but the wallet's allowance is known to be
  /// used up. False when the allowance could not be determined, so an
  /// unreachable endpoint never tells the user they ran out.
  bool get isFreeAllowanceExhausted =>
      freeStatus == FreeUploadStatus.allowanceUsedUp;

  // copy with
  UploadPaymentMethodInfo copyWith({
    UploadMethod? uploadMethod,
    UploadCostEstimate? costEstimateTurbo,
    UploadCostEstimate? costEstimateAr,
    bool? hasNoTurboBalance,
    bool? isTurboUploadPossible,
    String? arBalance,
    bool? sufficientArBalance,
    String? turboCredits,
    bool? sufficentCreditsBalance,
    FreeUploadStatus? freeStatus,
    UploadPlan? uploadPlanForAR,
    UploadPlan? uploadPlanForTurbo,
    int? totalSize,
    List<String>? paidBy,
    SourceWalletCredits? sourceWalletCredits,
    BigInt? turboBalanceWinc,
    bool? turboUnreachable,
    bool? arChosen,
  }) {
    return UploadPaymentMethodInfo(
      totalSize: totalSize ?? this.totalSize,
      uploadPlanForAR: uploadPlanForAR ?? this.uploadPlanForAR,
      uploadPlanForTurbo: uploadPlanForTurbo ?? this.uploadPlanForTurbo,
      uploadMethod: uploadMethod ?? this.uploadMethod,
      costEstimateTurbo: costEstimateTurbo ?? this.costEstimateTurbo,
      costEstimateAr: costEstimateAr ?? this.costEstimateAr,
      hasNoTurboBalance: hasNoTurboBalance ?? this.hasNoTurboBalance,
      isTurboUploadPossible:
          isTurboUploadPossible ?? this.isTurboUploadPossible,
      arBalance: arBalance ?? this.arBalance,
      sufficientArBalance: sufficientArBalance ?? this.sufficientArBalance,
      turboCredits: turboCredits ?? this.turboCredits,
      sufficentCreditsBalance:
          sufficentCreditsBalance ?? this.sufficentCreditsBalance,
      freeStatus: freeStatus ?? this.freeStatus,
      paidBy: paidBy ?? this.paidBy,
      sourceWalletCredits: sourceWalletCredits ?? this.sourceWalletCredits,
      turboBalanceWinc: turboBalanceWinc ?? this.turboBalanceWinc,
      turboUnreachable: turboUnreachable ?? this.turboUnreachable,
      arChosen: arChosen ?? this.arChosen,
    );
  }

  @override
  List<Object?> get props => [
        uploadMethod,
        costEstimateTurbo,
        costEstimateAr,
        hasNoTurboBalance,
        isTurboUploadPossible,
        arBalance,
        sufficientArBalance,
        turboCredits,
        sufficentCreditsBalance,
        freeStatus,
        paidBy,
        sourceWalletCredits,
        turboBalanceWinc,
        turboUnreachable,
        arChosen,
      ];
}

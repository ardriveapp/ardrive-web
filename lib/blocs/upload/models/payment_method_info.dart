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
      ];
}

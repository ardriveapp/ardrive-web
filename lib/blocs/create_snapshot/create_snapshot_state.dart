part of 'create_snapshot_cubit.dart';

@immutable
abstract class CreateSnapshotState extends Equatable {
  @override
  List<Object> get props => [];
}

class CreateSnapshotInitial extends CreateSnapshotState {}

class ComputingSnapshotData extends CreateSnapshotState {
  final DriveID driveId;
  final Range range;
  final int processedTransactions;
  final int totalTransactions;

  ComputingSnapshotData({
    required this.driveId,
    required this.range,
    this.processedTransactions = 0,
    this.totalTransactions = 0,
  });

  @override
  List<Object> get props =>
      [driveId, range, processedTransactions, totalTransactions];
}

class PreparingAndSigningTransaction extends CreateSnapshotState {
  final bool isArConnectProfile;

  PreparingAndSigningTransaction({required this.isArConnectProfile});

  @override
  List<Object> get props => [isArConnectProfile];
}

class ComputeSnapshotDataFailure extends CreateSnapshotState {
  final String errorMessage;

  ComputeSnapshotDataFailure({required this.errorMessage});

  @override
  List<Object> get props => [errorMessage];
}

class CreateSnapshotInsufficientBalance extends CreateSnapshotState {
  final String walletBalance;
  final String arCost;

  CreateSnapshotInsufficientBalance({
    required this.walletBalance,
    required this.arCost,
  });

  @override
  List<Object> get props => [walletBalance, arCost];
}

class ConfirmingSnapshotCreation extends CreateSnapshotState {
  final int snapshotSize;

  final UploadCostEstimate costEstimateAr;
  final UploadCostEstimate? costEstimateTurbo;
  final bool hasNoTurboBalance;
  final bool isTurboUploadPossible;
  final String arBalance;
  final String turboCredits;
  final UploadMethod uploadMethod;
  final bool isButtonToUploadEnabled;
  final bool sufficientBalanceToPayWithAr;
  final bool sufficientBalanceToPayWithTurbo;

  /// Whether this snapshot upload is free, and if not, why not.
  final FreeUploadStatus freeStatus;

  ConfirmingSnapshotCreation({
    required this.snapshotSize,
    required this.costEstimateAr,
    required this.costEstimateTurbo,
    required this.hasNoTurboBalance,
    required this.isTurboUploadPossible,
    required this.arBalance,
    required this.turboCredits,
    required this.uploadMethod,
    required this.isButtonToUploadEnabled,
    required this.sufficientBalanceToPayWithAr,
    required this.sufficientBalanceToPayWithTurbo,
    required this.freeStatus,
  });

  bool get isFreeThanksToTurbo => freeStatus == FreeUploadStatus.free;

  /// Small enough to be free, but the allowance is known to be used up.
  bool get isFreeAllowanceExhausted =>
      freeStatus == FreeUploadStatus.allowanceUsedUp;

  @override
  List<Object> get props => [
        snapshotSize,
        costEstimateAr,
        costEstimateTurbo ?? '',
        hasNoTurboBalance,
        isTurboUploadPossible,
        arBalance,
        turboCredits,
        uploadMethod,
        isButtonToUploadEnabled,
        sufficientBalanceToPayWithAr,
        sufficientBalanceToPayWithTurbo,
        freeStatus,
      ];

  ConfirmingSnapshotCreation copyWith({
    int? snapshotSize,
    String? arUploadCost,
    double? usdUploadCost,
    UploadCostEstimate? costEstimateAr,
    UploadCostEstimate? costEstimateTurbo,
    bool? hasNoTurboBalance,
    bool? isTurboUploadPossible,
    String? arBalance,
    String? turboCredits,
    UploadMethod? uploadMethod,
    bool? isButtonToUploadEnabled,
    bool? sufficientBalanceToPayWithAr,
    bool? sufficientBalanceToPayWithTurbo,
    FreeUploadStatus? freeStatus,
  }) {
    return ConfirmingSnapshotCreation(
      snapshotSize: snapshotSize ?? this.snapshotSize,
      costEstimateAr: costEstimateAr ?? this.costEstimateAr,
      costEstimateTurbo: costEstimateTurbo ?? this.costEstimateTurbo,
      hasNoTurboBalance: hasNoTurboBalance ?? this.hasNoTurboBalance,
      isTurboUploadPossible:
          isTurboUploadPossible ?? this.isTurboUploadPossible,
      arBalance: arBalance ?? this.arBalance,
      turboCredits: turboCredits ?? this.turboCredits,
      uploadMethod: uploadMethod ?? this.uploadMethod,
      isButtonToUploadEnabled:
          isButtonToUploadEnabled ?? this.isButtonToUploadEnabled,
      sufficientBalanceToPayWithAr:
          sufficientBalanceToPayWithAr ?? this.sufficientBalanceToPayWithAr,
      sufficientBalanceToPayWithTurbo: sufficientBalanceToPayWithTurbo ??
          this.sufficientBalanceToPayWithTurbo,
      freeStatus: freeStatus ?? this.freeStatus,
    );
  }
}

class UploadingSnapshot extends CreateSnapshotState {}

class SnapshotUploadFailure extends CreateSnapshotState {
  final bool isPaymentError;
  SnapshotUploadFailure({this.isPaymentError = false});

  @override
  List<Object> get props => [isPaymentError];
}

class SnapshotUploadSuccess extends CreateSnapshotState {}

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

  ComputingSnapshotData({
    required this.driveId,
    required this.range,
  });

  @override
  List<Object> get props => [driveId, range];
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
  final bool isFreeThanksToTurbo;

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
    required this.isFreeThanksToTurbo,
  });

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
        isFreeThanksToTurbo,
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
    bool? isFreeThanksToTurbo,
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
      isFreeThanksToTurbo: isFreeThanksToTurbo ?? this.isFreeThanksToTurbo,
    );
  }
}

class UploadingSnapshot extends CreateSnapshotState {}

class SnapshotUploadFailure extends CreateSnapshotState {
  @override
  List<Object> get props => [];
}

class SnapshotUploadSuccess extends CreateSnapshotState {}

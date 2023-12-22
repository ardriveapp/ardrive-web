import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';

abstract class HideState extends Equatable {
  const HideState();
}

class InitialHideState extends HideState {
  const InitialHideState();

  @override
  List<Object?> get props => [];
}

class UploadingHideState extends HideState {
  const UploadingHideState();

  @override
  List<Object?> get props => [];
}

class PreparingAndSigningHideState extends HideState {
  const PreparingAndSigningHideState();

  @override
  List<Object?> get props => [];
}

class ConfirmingHideState extends HideState {
  final UploadMethod uploadMethod;
  final UploadCostEstimate? costEstimateTurbo;
  final UploadCostEstimate costEstimateAr;
  final bool hasNoTurboBalance;
  final bool isTurboUploadPossible;
  final String arBalance;
  final bool sufficientArBalance;
  final String turboCredits;
  final bool sufficentCreditsBalance;
  final bool isFreeThanksToTurbo;
  final bool isButtonToUploadEnabled;
  final HideAction hideAction;

  final List<DataItem> dataItems;
  final Future<void> Function() saveEntitiesToDb;

  const ConfirmingHideState({
    required this.uploadMethod,
    required this.costEstimateTurbo,
    required this.costEstimateAr,
    required this.hasNoTurboBalance,
    required this.isTurboUploadPossible,
    required this.arBalance,
    required this.sufficientArBalance,
    required this.turboCredits,
    required this.sufficentCreditsBalance,
    required this.isFreeThanksToTurbo,
    required this.isButtonToUploadEnabled,
    required this.hideAction,
    required this.dataItems,
    required this.saveEntitiesToDb,
  });

  @override
  List<Object> get props => [
        uploadMethod,
        costEstimateTurbo ?? '',
        costEstimateAr,
        hasNoTurboBalance,
        isTurboUploadPossible,
        arBalance,
        sufficientArBalance,
        turboCredits,
        sufficentCreditsBalance,
        isFreeThanksToTurbo,
        isButtonToUploadEnabled,
        hideAction,
      ];

  ConfirmingHideState copyWith({
    UploadMethod? uploadMethod,
    UploadCostEstimate? costEstimateTurbo,
    UploadCostEstimate? costEstimateAr,
    bool? hasNoTurboBalance,
    bool? isTurboUploadPossible,
    String? arBalance,
    bool? sufficientArBalance,
    String? turboCredits,
    bool? sufficentCreditsBalance,
    bool? isFreeThanksToTurbo,
    bool? isButtonToUploadEnabled,
    HideAction? hideAction,
  }) {
    return ConfirmingHideState(
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
      isFreeThanksToTurbo: isFreeThanksToTurbo ?? this.isFreeThanksToTurbo,
      isButtonToUploadEnabled:
          isButtonToUploadEnabled ?? this.isButtonToUploadEnabled,
      hideAction: hideAction ?? this.hideAction,
      dataItems: dataItems,
      saveEntitiesToDb: saveEntitiesToDb,
    );
  }
}

class SuccessHideState extends HideState {
  const SuccessHideState();

  @override
  List<Object?> get props => [];
}

class FailureHideState extends HideState {
  final String message;

  const FailureHideState({
    required this.message,
  });

  @override
  List<Object?> get props => [message];
}

enum HideAction {
  hideFile,
  hideFolder,
  unhideFile,
  unhideFolder,
}

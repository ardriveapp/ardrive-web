import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';

abstract class HideState extends Equatable {
  final HideAction hideAction;

  const HideState({
    required this.hideAction,
  });

  @override
  List<Object?> get props => [hideAction];
}

class InitialHideState extends HideState {
  const InitialHideState() : super(hideAction: HideAction.hideFile);
}

class UploadingHideState extends HideState {
  const UploadingHideState({required super.hideAction});
}

class PreparingAndSigningHideState extends HideState {
  const PreparingAndSigningHideState({required super.hideAction});
}

class ConfirmingHideState extends HideState {
  final UploadMethod uploadMethod;
  final HideEntitySettings hideEntitySettings;
  final List<DataItem> dataItems;

  const ConfirmingHideState({
    required this.uploadMethod,
    required super.hideAction,
    required this.dataItems,
    required this.hideEntitySettings,
  });

  @override
  List<Object> get props => [
        uploadMethod,
        hideAction,
      ];

  ConfirmingHideState copyWith({
    UploadMethod? uploadMethod,
    UploadCostEstimate? costEstimateTurbo,
    UploadCostEstimate? costEstimateAr,
    HideAction? hideAction,
    HideEntitySettings? hideEntitySettings,
  }) {
    return ConfirmingHideState(
      uploadMethod: uploadMethod ?? this.uploadMethod,
      hideAction: hideAction ?? this.hideAction,
      dataItems: dataItems,
      hideEntitySettings: hideEntitySettings ?? this.hideEntitySettings,
    );
  }
}

class SuccessHideState extends HideState {
  const SuccessHideState({required super.hideAction});
}

class FailureHideState extends HideState {
  const FailureHideState({required super.hideAction});
}

enum HideAction {
  hideFile,
  hideFolder,
  hideDrive,
  unhideFile,
  unhideFolder,
  unhideDrive,
}

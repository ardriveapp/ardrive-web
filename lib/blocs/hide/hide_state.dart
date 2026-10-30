import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
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

  /// What writing the change costs, and who pays. Null while it is read.
  final MetadataWriteCost? cost;

  /// Turbo refused the write as not paid for: the review shows, never the
  /// instant write.
  final bool refused;

  const ConfirmingHideState({
    required this.uploadMethod,
    required super.hideAction,
    required this.dataItems,
    required this.hideEntitySettings,
    this.cost,
    this.refused = false,
  });

  UploadReviewSummary? get summary => cost?.summary;

  /// Free, and Turbo has not said otherwise: written straight away, with no
  /// review, as hiding always has been.
  bool get isInstant => !refused && (summary?.isFree ?? false);

  @override
  List<Object?> get props => [
        uploadMethod,
        hideAction,
        summary,
        refused,
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
      cost: cost,
      refused: refused,
    );
  }
}

class SuccessHideState extends HideState {
  const SuccessHideState({required super.hideAction});
}

/// The write failed. Turbo refusing it as not paid for is not a failure:
/// that goes back to [ConfirmingHideState], with Add credits.
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

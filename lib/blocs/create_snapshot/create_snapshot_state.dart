part of 'create_snapshot_cubit.dart';

@immutable
abstract class CreateSnapshotState extends Equatable {
  @override
  List<Object> get props => [];
}

/// Initial state where user begins by selecting a drive to snapshot and the height range
class CreateSnapshotInitial extends CreateSnapshotState {}

/// User has selected the drive and height range and we are computing the snapshot data
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

/// Snapshot data computation has failed
class ComputeSnapshotDataFailure extends CreateSnapshotState {
  final String errorMessage;

  ComputeSnapshotDataFailure({required this.errorMessage});

  @override
  List<Object> get props => [errorMessage];
}

class CreateSnapshotInsufficientBalance extends CreateSnapshotState {
  final String walletBalance;
  final String totalCost;

  CreateSnapshotInsufficientBalance({
    required this.walletBalance,
    required this.totalCost,
  });

  @override
  List<Object> get props => [walletBalance, totalCost];
}

/// Snapshot data has been computed and it's ready to be confirmed
class ConfirmingSnapshotCreation extends CreateSnapshotState {
  final int snapshotSize;
  final String arUploadCost;
  final double? usdUploadCost;
  final CreateSnapshotParameters createSnapshotParams;

  ConfirmingSnapshotCreation({
    required this.snapshotSize,
    required this.arUploadCost,
    required this.usdUploadCost,
    required this.createSnapshotParams,
  });

  @override
  List<Object> get props => [snapshotSize, arUploadCost, createSnapshotParams];
}

/// User has confirmed the upload and we are now uploading the snapshot
class UploadingSnapshot extends CreateSnapshotState {}

/// Upload has failed
class SnapshotUploadFailure extends CreateSnapshotState {
  final String errorMessage;

  SnapshotUploadFailure({required this.errorMessage});

  @override
  List<Object> get props => [errorMessage];
}

/// Upload has succeeded
class SnapshotUploadSuccess extends CreateSnapshotState {}

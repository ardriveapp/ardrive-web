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
  final String arUploadCost;
  final double? usdUploadCost;

  ConfirmingSnapshotCreation({
    required this.snapshotSize,
    required this.arUploadCost,
    required this.usdUploadCost,
  });

  @override
  List<Object> get props => [
        snapshotSize,
        arUploadCost,
      ];
}

class UploadingSnapshot extends CreateSnapshotState {}

class SnapshotUploadFailure extends CreateSnapshotState {
  final String errorMessage;

  SnapshotUploadFailure({required this.errorMessage});

  @override
  List<Object> get props => [errorMessage];
}

class SnapshotUploadSuccess extends CreateSnapshotState {}

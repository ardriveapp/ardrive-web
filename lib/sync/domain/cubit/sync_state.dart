part of 'sync_cubit.dart';

@immutable
abstract class SyncState extends Equatable {
  @override
  List<Object> get props => [];
}

class SyncIdle extends SyncState {}

class SyncInProgress extends SyncState {}

class SyncFailure extends SyncState {
  final Object? error;
  final StackTrace? stackTrace;

  SyncFailure({this.error, this.stackTrace});
}

class SyncEmpty extends SyncState {}

class SyncWalletMismatch extends SyncState {}

class SyncCancelled extends SyncState {
  final int drivesCompleted;
  final int totalDrives;
  final DateTime cancelledAt;

  SyncCancelled({
    required this.drivesCompleted,
    required this.totalDrives,
    required this.cancelledAt,
  });

  @override
  List<Object> get props => [drivesCompleted, totalDrives, cancelledAt];
}

class SyncCompleteWithErrors extends SyncState {
  final int failedDrives;
  final int totalDrives;
  final List<String> failedDriveIds;
  final Map<String, String> errorMessages;

  SyncCompleteWithErrors({
    required this.failedDrives,
    required this.totalDrives,
    required this.failedDriveIds,
    required this.errorMessages,
  });

  @override
  List<Object> get props => [failedDrives, totalDrives, failedDriveIds, errorMessages];
}

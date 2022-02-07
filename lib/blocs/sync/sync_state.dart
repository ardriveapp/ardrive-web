part of 'sync_cubit.dart';

@immutable
abstract class SyncState extends Equatable {
  @override
  List<Object?> get props => [];
}

class SyncIdle extends SyncState {}

class SyncInProgress extends SyncState {
  final String? driveName;
  final int? lastBlockHeight;
  final int? maxBlockHeight;
  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;

  SyncInProgress({
    this.driveName,
    this.lastBlockHeight,
    this.maxBlockHeight,
  });

  @override
  List<Object?> get props => [
        driveName,
        lastBlockHeight,
        maxBlockHeight,
        _equatableBust,
      ];
}

class SyncFailure extends SyncState {
  final Object? error;
  final StackTrace? stackTrace;

  SyncFailure({this.error, this.stackTrace});
}

class SyncEmpty extends SyncState {}

class SyncWalletMismatch extends SyncState {}

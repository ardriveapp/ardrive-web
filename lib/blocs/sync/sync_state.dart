part of 'sync_cubit.dart';

@immutable
abstract class SyncState extends Equatable {
  @override
  List<Object> get props => [];
}

class SyncIdle extends SyncState {}

class SyncInProgress extends SyncState {}

class SyncFailure extends SyncState {
  final Object error;
  final StackTrace stackTrace;

  SyncFailure({this.error, this.stackTrace});
}

class SyncEmpty extends SyncState {}

class SyncWalletMismatch extends SyncState {}

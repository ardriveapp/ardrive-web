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

class SyncEmpty extends SyncState {
  final Map<String, OrphanParent> orphanParents;
  SyncEmpty({required this.orphanParents});
  @override
  List<Object> get props => [orphanParents];
}

class SyncWalletMismatch extends SyncState {}

class OrphanParent {
  String id;
  String parentFolderId;
  String driveId;
  int orphanCount;
  OrphanParent({
    required this.id,
    required this.parentFolderId,
    required this.driveId,
    required this.orphanCount,
  });
}

part of 'sync_bloc.dart';

@immutable
abstract class SyncState {}

class SyncNotRunning extends SyncState {}

class SyncInProgress extends SyncState {}

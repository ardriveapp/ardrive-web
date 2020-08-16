part of 'sync_bloc.dart';

@immutable
abstract class SyncState {}

class SyncIdle extends SyncState {}

class SyncInProgress extends SyncState {}

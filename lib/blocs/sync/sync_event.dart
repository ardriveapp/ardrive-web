part of 'sync_bloc.dart';

@immutable
abstract class SyncEvent {}

class SyncWithNetwork extends SyncEvent {}

part of 'sync_bloc.dart';

@immutable
abstract class SyncEvent extends Equatable {
  @override
  List<Object> get props => [];
}

class SyncWithNetwork extends SyncEvent {}

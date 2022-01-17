part of 'activity_cubit.dart';

@immutable
abstract class ActivityState extends Equatable {
  const ActivityState();

  @override
  List<Object?> get props => [];
}

class ActivityInProgress extends ActivityState {}

class ActivityNotRunning extends ActivityState {}

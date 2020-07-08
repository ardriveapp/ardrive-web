part of 'drives_bloc.dart';

abstract class DrivesState {}

class DrivesLoadInProgress extends DrivesState {}

class DrivesLoadSuccess extends DrivesState {
  final List<Drive> drives;

  DrivesLoadSuccess(this.drives);
}

part of 'drives_bloc.dart';

abstract class DrivesState {}

class DrivesLoading extends DrivesState {}

class DrivesReady extends DrivesState {
  final String selectedDriveId;
  final List<Drive> drives;

  DrivesReady({this.selectedDriveId, this.drives});
}

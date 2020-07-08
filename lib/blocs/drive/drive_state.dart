import 'package:drive/models/drive.dart';

abstract class DriveState {}

class DriveLoadInProgress extends DriveState {}

class DriveLoadSuccess extends DriveState {
  final List<Drive> drives;

  DriveLoadSuccess(this.drives);
}

part of 'drive_detail_bloc.dart';

@immutable
abstract class DriveDetailState {}

class DriveDetailLoadSuccess extends DriveDetailState {
  final String openedFolderId;

  DriveDetailLoadSuccess(this.openedFolderId);
}

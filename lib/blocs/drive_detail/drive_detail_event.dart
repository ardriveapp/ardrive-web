part of 'drive_detail_bloc.dart';

@immutable
abstract class DriveDetailEvent {}

class OpenedFolder extends DriveDetailEvent {
  final String folderId;

  OpenedFolder(this.folderId);
}

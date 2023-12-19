import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';

abstract class HideEvent extends Equatable {
  const HideEvent();
}

class HideFileEvent extends HideEvent {
  final DriveID driveId;
  final FileID fileId;

  const HideFileEvent({required this.driveId, required this.fileId});

  @override
  List<Object> get props => [driveId, fileId];
}

class HideFolderEvent extends HideEvent {
  final DriveID driveId;
  final FolderID folderId;

  const HideFolderEvent({required this.driveId, required this.folderId});

  @override
  List<Object> get props => [driveId, folderId];
}

class UnhideFileEvent extends HideEvent {
  final DriveID driveId;
  final FileID fileId;

  const UnhideFileEvent({required this.driveId, required this.fileId});

  @override
  List<Object> get props => [driveId, fileId];
}

class UnhideFolderEvent extends HideEvent {
  final DriveID driveId;
  final FolderID folderId;

  const UnhideFolderEvent({required this.driveId, required this.folderId});

  @override
  List<Object> get props => [driveId, folderId];
}

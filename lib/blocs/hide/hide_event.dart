import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';

abstract class HideEvent extends Equatable {
  const HideEvent();
}

class HideFileEvent extends HideEvent {
  final DriveID driveId;
  final FileID fileId;

  const HideFileEvent({
    required this.driveId,
    required this.fileId,
  });

  @override
  List<Object> get props => [driveId, fileId];
}

class HideDriveEvent extends HideEvent {
  final DriveID driveId;

  const HideDriveEvent({
    required this.driveId,
  });

  @override
  List<Object> get props => [driveId];
}

class UnhideDriveEvent extends HideEvent {
  final DriveID driveId;

  const UnhideDriveEvent({
    required this.driveId,
  });

  @override
  List<Object> get props => [driveId];
}

class HideMultipleFilesEvent extends HideEvent {
  final DriveID driveId;
  final List<FileID> fileIds;

  const HideMultipleFilesEvent({
    required this.driveId,
    required this.fileIds,
  });

  @override
  List<Object> get props => [driveId, fileIds];
}

class UnhideMultipleFilesEvent extends HideEvent {
  final DriveID driveId;
  final List<FileID> fileIds;

  const UnhideMultipleFilesEvent({
    required this.driveId,
    required this.fileIds,
  });

  @override
  List<Object> get props => [driveId, fileIds];
}

class HideFolderEvent extends HideEvent {
  final DriveID driveId;
  final FolderID folderId;

  const HideFolderEvent({
    required this.driveId,
    required this.folderId,
  });

  @override
  List<Object> get props => [driveId, folderId];
}

class UnhideFileEvent extends HideEvent {
  final DriveID driveId;
  final FileID fileId;

  const UnhideFileEvent({
    required this.driveId,
    required this.fileId,
  });

  @override
  List<Object> get props => [driveId, fileId];
}

class UnhideFolderEvent extends HideEvent {
  final DriveID driveId;
  final FolderID folderId;

  const UnhideFolderEvent({
    required this.driveId,
    required this.folderId,
  });

  @override
  List<Object> get props => [driveId, folderId];
}

class ConfirmUploadEvent extends HideEvent {
  const ConfirmUploadEvent();

  @override
  List<Object> get props => [];
}

class SelectUploadMethodEvent extends HideEvent {
  final UploadMethod uploadMethod;

  const SelectUploadMethodEvent({
    required this.uploadMethod,
  });

  @override
  List<Object> get props => [uploadMethod];
}

class RefreshTurboBalanceEvent extends HideEvent {
  const RefreshTurboBalanceEvent();

  @override
  List<Object> get props => [];
}

class ErrorEvent extends HideEvent {
  final Object error;
  final StackTrace stackTrace;
  final HideAction hideAction;

  const ErrorEvent({
    required this.error,
    required this.stackTrace,
    required this.hideAction,
  });

  @override
  List<Object> get props => [
        error,
        stackTrace,
        hideAction,
      ];
}

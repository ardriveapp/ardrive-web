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

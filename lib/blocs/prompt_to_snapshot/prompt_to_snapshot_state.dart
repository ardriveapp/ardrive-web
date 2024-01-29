import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';

abstract class PromptToSnapshotState extends Equatable {
  final DriveID? driveId;

  const PromptToSnapshotState({
    required this.driveId,
  });

  @override
  List<Object> get props => [driveId ?? ''];
}

class PromptToSnapshotIdle extends PromptToSnapshotState {
  const PromptToSnapshotIdle() : super(driveId: null);
}

class PromptToSnapshotPrompting extends PromptToSnapshotState {
  @override
  String get driveId => super.driveId!;

  const PromptToSnapshotPrompting({
    required DriveID driveId,
  }) : super(driveId: driveId);

  PromptToSnapshotPrompting copyWith({
    String? driveId,
  }) {
    return PromptToSnapshotPrompting(
      driveId: driveId ?? this.driveId,
    );
  }
}

class PromptToSnapshotSnapshotting extends PromptToSnapshotState {
  @override
  String get driveId => super.driveId!;

  const PromptToSnapshotSnapshotting({
    required DriveID driveId,
  }) : super(driveId: driveId);

  PromptToSnapshotSnapshotting copyWith({
    String? driveId,
  }) {
    return PromptToSnapshotSnapshotting(
      driveId: driveId ?? this.driveId,
    );
  }
}

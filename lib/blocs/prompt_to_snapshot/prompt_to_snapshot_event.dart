import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';

abstract class PromptToSnapshotEvent extends Equatable {
  final DriveID? driveId;
  const PromptToSnapshotEvent({required this.driveId});

  @override
  List<Object> get props => [];
}

class CountSyncedTxs extends PromptToSnapshotEvent {
  final int txsSyncedWithGqlCount;
  final bool wasDeepSync;

  @override
  String get driveId => super.driveId!;

  const CountSyncedTxs({
    required DriveID driveId,
    required this.txsSyncedWithGqlCount,
    required this.wasDeepSync,
  }) : super(driveId: driveId);

  @override
  List<Object> get props => [driveId, txsSyncedWithGqlCount, wasDeepSync];
}

class SelectedDrive extends PromptToSnapshotEvent {
  const SelectedDrive({required super.driveId});
}

class SyncRunning extends PromptToSnapshotEvent {
  final bool isRunning;

  const SyncRunning({
    required this.isRunning,
  }) : super(driveId: null);

  @override
  List<Object> get props => [driveId ?? '', isRunning];
}

class DriveSnapshotting extends PromptToSnapshotEvent {
  @override
  String get driveId => super.driveId!;

  const DriveSnapshotting({required DriveID driveId}) : super(driveId: driveId);
}

class DriveSnapshotted extends PromptToSnapshotEvent {
  final int txsSyncedWithGqlCount;

  @override
  String get driveId => super.driveId!;

  const DriveSnapshotted({
    required DriveID driveId,
    this.txsSyncedWithGqlCount = 0,
  }) : super(driveId: driveId);

  @override
  List<Object> get props => [driveId, txsSyncedWithGqlCount];
}

class DismissDontAskAgain extends PromptToSnapshotEvent {
  final bool dontAskAgain;

  const DismissDontAskAgain({
    required this.dontAskAgain,
  }) : super(driveId: null);
}

class ClosePromptToSnapshot extends PromptToSnapshotEvent {
  const ClosePromptToSnapshot() : super(driveId: null);
}

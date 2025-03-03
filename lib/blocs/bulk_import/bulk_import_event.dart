import 'package:equatable/equatable.dart';

/// Events for the bulk import process.
abstract class BulkImportEvent extends Equatable {
  const BulkImportEvent();

  @override
  List<Object?> get props => [];
}

/// Event to start a bulk import using a manifest transaction ID
class StartManifestBulkImport extends BulkImportEvent {
  final String manifestTxId;
  final String driveId;
  final String parentFolderId;

  const StartManifestBulkImport({
    required this.manifestTxId,
    required this.driveId,
    required this.parentFolderId,
  });

  @override
  List<Object?> get props => [manifestTxId, driveId, parentFolderId];
}

/// Event to replace conflicting files
class ReplaceConflictingFiles extends BulkImportEvent {
  final String manifestTxId;
  final String driveId;
  final String parentFolderId;

  const ReplaceConflictingFiles({
    required this.manifestTxId,
    required this.driveId,
    required this.parentFolderId,
  });

  @override
  List<Object?> get props => [manifestTxId, driveId, parentFolderId];
}

/// Event to cancel the bulk import process
class CancelBulkImport extends BulkImportEvent {
  const CancelBulkImport();
}

/// Event to reset the bulk import state to initial.
class ResetBulkImport extends BulkImportEvent {
  const ResetBulkImport();
}

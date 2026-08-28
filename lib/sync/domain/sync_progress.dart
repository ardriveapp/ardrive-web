abstract class LinearProgress {
  double get progress;
}

/// Sentinel used by copyWith to distinguish "not provided" from "explicitly null".
const _absent = Object();

class SyncProgress extends LinearProgress {
  SyncProgress({
    required this.numberOfEntities,
    required this.progress,
    required this.entitiesSynced,
    required this.drivesCount,
    required this.drivesSynced,
    required this.numberOfDrivesAtGetMetadataPhase,
    this.failedQueries = 0,
    this.failedDriveIds = const [],
    this.errorMessages = const {},
    this.statusMessage,
    this.isSingleDriveSync = false,
    this.driveName,
    this.skippedEntityCount = 0,
    this.skippedEntityTxIdsByDrive = const {},
    this.firstTimeSyncDriveCount = 0,
    this.skippedDriveCount = 0,
  });

  factory SyncProgress.initial() {
    return SyncProgress(
      numberOfEntities: 0,
      progress: 0,
      entitiesSynced: 0,
      drivesCount: 0,
      drivesSynced: 0,
      numberOfDrivesAtGetMetadataPhase: 0,
      failedQueries: 0,
      failedDriveIds: const [],
      errorMessages: const {},
      statusMessage: null,
      isSingleDriveSync: false,
      driveName: null,
    );
  }

  factory SyncProgress.emptySyncCompleted() {
    return SyncProgress(
      numberOfEntities: 0,
      progress: 1,
      entitiesSynced: 0,
      drivesCount: 0,
      drivesSynced: 0,
      numberOfDrivesAtGetMetadataPhase: 0,
      failedQueries: 0,
      failedDriveIds: const [],
      errorMessages: const {},
      statusMessage: null,
      isSingleDriveSync: false,
      driveName: null,
    );
  }

  final int numberOfEntities;
  final int entitiesSynced;
  @override
  final double progress;
  final int drivesSynced;
  final int drivesCount;
  final int numberOfDrivesAtGetMetadataPhase;

  // New fields for tracking failures
  final int failedQueries;
  final List<String> failedDriveIds;
  final Map<String, String> errorMessages; // driveId -> error message
  final String? statusMessage; // Status message for post-sync operations

  // Fields for distinguishing sync type
  final bool isSingleDriveSync; // true if syncing a single drive
  final String? driveName; // name of the drive being synced (for single drive sync)

  /// Number of entities left out of this sync because their metadata could not
  /// be read from the configured gateway.
  final int skippedEntityCount;

  /// The skipped entities' transaction ids, keyed by drive id. This is the
  /// only record that anything was dropped — a later pass surfaces these as
  /// "failed files" in the UI. See `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md`.
  final Map<String, List<String>> skippedEntityTxIdsByDrive;

  /// Number of drives in this sync that are read from the start of their
  /// history rather than from a watermark, and so cost a full history walk:
  /// the drives that have never been synced before, and — in a deep sync,
  /// which rewinds every drive to block zero — all of them.
  final int firstTimeSyncDriveCount;

  /// Number of drives the activity probe found unchanged and left out of this
  /// sync. Zero for a deep sync, and zero when the probe could not answer -
  /// in both of those cases nothing was skipped.
  final int skippedDriveCount;

  /// Flat list of every skipped transaction id, drive association discarded.
  List<String> get skippedEntityTxIds =>
      [...skippedEntityTxIdsByDrive.values.expand((txIds) => txIds)];

  // Helper getters
  bool get hasErrors => failedQueries > 0;

  bool get hasSkippedEntities => skippedEntityCount > 0;
  bool get isPartialSync => hasErrors && progress >= 1.0;
  bool get isCompleteWithErrors => progress >= 1.0 && hasErrors;

  SyncProgress copyWith({
    int? numberOfEntities,
    int? entitiesSynced,
    double? progress,
    int? drivesSynced,
    int? drivesCount,
    int? numberOfDrivesAtGetMetadataPhase,
    int? failedQueries,
    List<String>? failedDriveIds,
    Map<String, String>? errorMessages,
    Object? statusMessage = _absent,
    bool? isSingleDriveSync,
    Object? driveName = _absent,
    int? skippedEntityCount,
    Map<String, List<String>>? skippedEntityTxIdsByDrive,
    int? firstTimeSyncDriveCount,
    int? skippedDriveCount,
  }) {
    return SyncProgress(
      numberOfEntities: numberOfEntities ?? this.numberOfEntities,
      progress: progress ?? this.progress,
      entitiesSynced: entitiesSynced ?? this.entitiesSynced,
      drivesCount: drivesCount ?? this.drivesCount,
      drivesSynced: drivesSynced ?? this.drivesSynced,
      numberOfDrivesAtGetMetadataPhase: numberOfDrivesAtGetMetadataPhase ??
          this.numberOfDrivesAtGetMetadataPhase,
      failedQueries: failedQueries ?? this.failedQueries,
      failedDriveIds: failedDriveIds ?? this.failedDriveIds,
      errorMessages: errorMessages ?? this.errorMessages,
      statusMessage: statusMessage == _absent
          ? this.statusMessage
          : statusMessage as String?,
      isSingleDriveSync: isSingleDriveSync ?? this.isSingleDriveSync,
      driveName:
          driveName == _absent ? this.driveName : driveName as String?,
      skippedEntityCount: skippedEntityCount ?? this.skippedEntityCount,
      skippedEntityTxIdsByDrive:
          skippedEntityTxIdsByDrive ?? this.skippedEntityTxIdsByDrive,
      firstTimeSyncDriveCount:
          firstTimeSyncDriveCount ?? this.firstTimeSyncDriveCount,
      skippedDriveCount: skippedDriveCount ?? this.skippedDriveCount,
    );
  }
}

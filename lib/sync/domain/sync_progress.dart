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
    this.examinedDriveIds = const {},
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

  /// The drives this sync opened and read — **not** every drive attached.
  ///
  /// A sync reports skips only for drives it examined, and its silence about
  /// the rest is not evidence about them. The activity probe skips drives it
  /// believes unchanged, and those drives are neither synced nor failed: they
  /// appear in no list this report carries. Naming what was examined is what
  /// lets a reader tell "this sync looked and found nothing to skip" apart
  /// from "this sync never looked".
  ///
  /// What reads it is `SyncCubit`'s per-drive skip ledger, and through that
  /// `driveStateSyncSkipStatus` — the precondition on publishing a drive
  /// state artifact, which records permanently and immutably on Arweave
  /// whatever gap it was built over. So this is populated **before** the first
  /// drive is touched rather than at the end: a sync that dies part-way must
  /// still have said which drives it may have already advanced.
  final Set<String> examinedDriveIds;

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
    Set<String>? examinedDriveIds,
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
      examinedDriveIds: examinedDriveIds ?? this.examinedDriveIds,
    );
  }
}

abstract class LinearProgress {
  double get progress;

  /// Whether [progress] is a real measurement right now, or a number standing
  /// in for work whose length nothing here can know. A bar reading an
  /// indeterminate progress should animate rather than draw [progress].
  bool get isIndeterminate => false;
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
    this.syncedDriveIds = const [],
    this.errorMessages = const {},
    this.statusMessage,
    this.isSingleDriveSync = false,
    this.driveName,
    this.skippedEntityCount = 0,
    this.skippedEntityTxIdsByDrive = const {},
    this.firstTimeSyncDriveCount = 0,
    this.skippedDriveCount = 0,
    this.isIndeterminate = false,
    this.metadataFetchesCompleted = 0,
    this.metadataFetchesTotal = 0,
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

  /// The drives this sync walked all the way to the end.
  ///
  /// Kept as ids rather than a count because it is the only thing that can
  /// answer "when was *this* drive last synced": the count says how many
  /// finished, never which. Failures are not in here - a drive that could not
  /// be read was not synced.
  final List<String> syncedDriveIds;
  final Map<String, String> errorMessages; // driveId -> error message
  final String? statusMessage; // Status message for post-sync operations

  // Fields for distinguishing sync type
  final bool isSingleDriveSync; // true if syncing a single drive
  final String?
      driveName; // name of the drive being synced (for single drive sync)

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

  /// Entity metadata bodies this sync has finished with, and how many it has
  /// asked for, counted across the whole sync rather than per drive or per
  /// batch.
  ///
  /// This is the one number that moves during the longest phase of a sync.
  /// Every file and folder revision's metadata is a separate HTTP round trip,
  /// run `maxConcurrentDataFetches` at a time, and nothing else the sync
  /// reports advances while those are in flight: `progress` is read off block
  /// heights the walk has not reached yet, and [entitiesSynced] only moves
  /// when a whole batch's fetches are done and its revisions are written. A
  /// drive with three thousand revisions therefore sat on one unchanging line
  /// for minutes.
  ///
  /// Both climb and neither is ever republished lower. [metadataFetchesTotal]
  /// is what has been asked for so far, not a prediction of the drive's size:
  /// history arrives in chunks, so it grows as the walk finds more, and it is
  /// never a figure the sync does not yet have. Zero on both means there is no
  /// fetch to report - before the first batch, and after the walk is over -
  /// and the surfaces fall back to what they said before this existed.
  final int metadataFetchesCompleted;
  final int metadataFetchesTotal;

  /// True while the sync is inside a phase whose length it cannot know and
  /// whose progress it cannot measure - today, the gateway round trip that
  /// asks which pending transactions confirmed. That phase reports one step
  /// per 5000 pending transactions, which for almost every user is one step,
  /// landing only when the gateway answers.
  ///
  /// No weighting makes a determinate bar move through that honestly, so it
  /// does not pretend to: [progress] holds where the phase began and the UI
  /// draws an indeterminate bar instead. Cleared as soon as the gateway is
  /// done with, however that went.
  @override
  final bool isIndeterminate;

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
    List<String>? syncedDriveIds,
    Map<String, String>? errorMessages,
    Object? statusMessage = _absent,
    bool? isSingleDriveSync,
    Object? driveName = _absent,
    int? skippedEntityCount,
    Map<String, List<String>>? skippedEntityTxIdsByDrive,
    int? firstTimeSyncDriveCount,
    int? skippedDriveCount,
    bool? isIndeterminate,
    int? metadataFetchesCompleted,
    int? metadataFetchesTotal,
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
      syncedDriveIds: syncedDriveIds ?? this.syncedDriveIds,
      errorMessages: errorMessages ?? this.errorMessages,
      statusMessage: statusMessage == _absent
          ? this.statusMessage
          : statusMessage as String?,
      isSingleDriveSync: isSingleDriveSync ?? this.isSingleDriveSync,
      driveName: driveName == _absent ? this.driveName : driveName as String?,
      skippedEntityCount: skippedEntityCount ?? this.skippedEntityCount,
      skippedEntityTxIdsByDrive:
          skippedEntityTxIdsByDrive ?? this.skippedEntityTxIdsByDrive,
      firstTimeSyncDriveCount:
          firstTimeSyncDriveCount ?? this.firstTimeSyncDriveCount,
      skippedDriveCount: skippedDriveCount ?? this.skippedDriveCount,
      isIndeterminate: isIndeterminate ?? this.isIndeterminate,
      metadataFetchesCompleted:
          metadataFetchesCompleted ?? this.metadataFetchesCompleted,
      metadataFetchesTotal: metadataFetchesTotal ?? this.metadataFetchesTotal,
    );
  }
}

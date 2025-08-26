abstract class LinearProgress {
  double get progress;
}

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
  
  // Helper getters
  bool get hasErrors => failedQueries > 0;
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
    String? statusMessage,
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
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

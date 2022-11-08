part of 'sync_cubit.dart';

abstract class LinearProgress {
  double get progress;
}

class SyncProgress extends LinearProgress {
  SyncProgress(
      {required this.entitiesNumber,
      required this.progress,
      required this.entitiesSynced,
      required this.drivesCount,
      required this.drivesSynced,
      required this.numberOfDrivesAtGetMetadataPhase});

  factory SyncProgress.initial() => SyncProgress(
        entitiesNumber: 0,
        progress: 0,
        entitiesSynced: 0,
        drivesCount: 0,
        drivesSynced: 0,
        numberOfDrivesAtGetMetadataPhase: 0,
      );

  factory SyncProgress.emptySyncCompleted() => SyncProgress(
        entitiesNumber: 0,
        progress: 1,
        entitiesSynced: 0,
        drivesCount: 0,
        drivesSynced: 0,
        numberOfDrivesAtGetMetadataPhase: 0,
      );

  final int entitiesNumber;
  final int entitiesSynced;
  @override
  final double progress;
  final int drivesSynced;
  final int drivesCount;
  final int numberOfDrivesAtGetMetadataPhase;

  SyncProgress copyWith(
          {int? entitiesNumber,
          int? entitiesSynced,
          double? progress,
          int? drivesSynced,
          int? drivesCount,
          int? numberOfDrivesAtGetMetadataPhase}) =>
      SyncProgress(
        entitiesNumber: entitiesNumber ?? this.entitiesNumber,
        progress: progress ?? this.progress,
        entitiesSynced: entitiesSynced ?? this.entitiesSynced,
        drivesCount: drivesCount ?? this.drivesCount,
        drivesSynced: drivesSynced ?? this.drivesSynced,
        numberOfDrivesAtGetMetadataPhase: numberOfDrivesAtGetMetadataPhase ??
            this.numberOfDrivesAtGetMetadataPhase,
      );
}

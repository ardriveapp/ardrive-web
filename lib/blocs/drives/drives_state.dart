part of 'drives_cubit.dart';

abstract class DrivesState extends Equatable {
  @override
  List<Object?> get props => [];
}

class DrivesLoadInProgress extends DrivesState {}

class DrivesLoadSuccess extends DrivesState {
  /// The id of the user's selected drive.
  ///
  /// Only null when the user has no drives.
  final String? selectedDriveId;

  final List<Drive> userDrives;
  final List<Drive> sharedDrives;

  final List<String> drivesWithAlerts;
  final bool canCreateNewDrive;
  final Set<String> lockedDrives;

  bool get hasNoDrives => userDrives.isEmpty && sharedDrives.isEmpty;
  bool isDriveLocked(String driveId) => lockedDrives.contains(driveId);
  
  DrivesLoadSuccess({
    required this.selectedDriveId,
    required this.userDrives,
    required this.sharedDrives,
    required this.drivesWithAlerts,
    required this.canCreateNewDrive,
    this.lockedDrives = const {},
  });

  DrivesLoadSuccess copyWith({
    String? selectedDriveId,
    List<Drive>? userDrives,
    List<Drive>? sharedDrives,
    List<String>? drivesWithAlerts,
    bool? canCreateNewDrive,
    Set<String>? lockedDrives,
  }) =>
      DrivesLoadSuccess(
        selectedDriveId: selectedDriveId ?? this.selectedDriveId,
        userDrives: userDrives ?? this.userDrives,
        sharedDrives: sharedDrives ?? this.sharedDrives,
        drivesWithAlerts: drivesWithAlerts ?? this.drivesWithAlerts,
        canCreateNewDrive: canCreateNewDrive ?? this.canCreateNewDrive,
        lockedDrives: lockedDrives ?? this.lockedDrives,
      );

  @override
  List<Object?> get props => [
        selectedDriveId,
        userDrives,
        sharedDrives,
        drivesWithAlerts,
        canCreateNewDrive,
        lockedDrives,
      ];
}

class DrivesLoadedWithNoDrivesFound extends DrivesLoadSuccess {
  DrivesLoadedWithNoDrivesFound({
    required super.canCreateNewDrive,
  }) : super(
          selectedDriveId: null,
          userDrives: [],
          sharedDrives: [],
          drivesWithAlerts: [],
        );
}

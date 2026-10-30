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

  /// The user's private drives this session can't open. Never in
  /// [userDrives]: they have no row and no name. See [LockedDrive].
  final List<LockedDrive> lockedDrives;

  final List<String> drivesWithAlerts;
  final bool canCreateNewDrive;

  /// Whether the user has no drive at all, locked ones included: an account
  /// whose only drives are locked is not an empty account.
  bool get hasNoDrives =>
      userDrives.isEmpty && sharedDrives.isEmpty && lockedDrives.isEmpty;

  DrivesLoadSuccess({
    required this.selectedDriveId,
    required this.userDrives,
    required this.sharedDrives,
    required this.drivesWithAlerts,
    required this.canCreateNewDrive,
    this.lockedDrives = const [],
  });

  DrivesLoadSuccess copyWith({
    String? selectedDriveId,
    List<Drive>? userDrives,
    List<Drive>? sharedDrives,
    List<String>? drivesWithAlerts,
    bool? canCreateNewDrive,
    List<LockedDrive>? lockedDrives,
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
        lockedDrives,
        drivesWithAlerts,
        canCreateNewDrive,
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

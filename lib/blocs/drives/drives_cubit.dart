import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

part 'drives_state.dart';

/// [DrivesCubit] includes logic for displaying the drives attached in the app.
/// It works even if the user profile is unavailable.
class DrivesCubit extends Cubit<DrivesState> {
  final ProfileCubit _profileCubit;
  final PromptToSnapshotBloc _promptToSnapshotBloc;
  final DriveDao _driveDao;
  final ArDriveAuth _auth;
  final UserPreferencesRepository _userPreferencesRepository;

  late StreamSubscription _drivesSubscription;
  String? initialSelectedDriveId;
  DrivesCubit({
    required ArDriveAuth auth,
    this.initialSelectedDriveId,
    required ProfileCubit profileCubit,
    required PromptToSnapshotBloc promptToSnapshotBloc,
    required DriveDao driveDao,
    required ActivityTracker activityTracker,
    required UserPreferencesRepository userPreferencesRepository,
  })  : _profileCubit = profileCubit,
        _promptToSnapshotBloc = promptToSnapshotBloc,
        _driveDao = driveDao,
        _auth = auth,
        _userPreferencesRepository = userPreferencesRepository,
        super(DrivesLoadInProgress()) {
    _auth.onAuthStateChanged().listen((user) {
      if (user == null) {
        cleanDrives();
        return;
      }
    });

    _drivesSubscription =
        Rx.combineLatest3<List<Drive>, List<FolderEntry>, void, List<Drive>>(
      _driveDao.allDrives(
        order: (drives) {
          return OrderBy([OrderingTerm.asc(drives.name)]);
        },
      ).watch(),
      _driveDao.ghostFolders().watch(),
      _profileCubit.stream.startWith(ProfileCheckingAvailability()),
      (drives, _, __) => drives,
    ).listen((drives) async {
      final state = this.state;

      final profileState = _profileCubit.state;

      if (profileState is ProfileLoggingIn) {
        emit(DrivesLoadInProgress());
        return;
      }

      String? selectedDriveId;

      if (state is DrivesLoadSuccess) {
        selectedDriveId = state.selectedDriveId;
      }

      if (selectedDriveId == null) {
        if (initialSelectedDriveId != null &&
            initialSelectedDriveId!.isNotEmpty) {
          selectedDriveId = initialSelectedDriveId;
        } else {
          final userPreferences = await _userPreferencesRepository.load();

          final userHasHiddenDrive = drives.any((d) => d.isHidden);
          await _userPreferencesRepository
              .saveUserHasHiddenItem(userHasHiddenDrive);

          selectedDriveId = userPreferences.lastSelectedDriveId;

          if (selectedDriveId == null ||
              !drives.any((d) => d.id == selectedDriveId)) {
            selectedDriveId = drives.isNotEmpty ? drives.first.id : null;
          }
        }
      }

      final walletAddress = profileState is ProfileLoggedIn
          ? profileState.user.walletAddress
          : null;

      final ghostFolders = await _driveDao.ghostFolders().get();

      final sharedDrives =
          drives.where((d) => !isDriveOwner(auth, d.ownerAddress)).toList();

      final userDrives = drives
          .where((d) => profileState is ProfileLoggedIn
              ? d.ownerAddress == walletAddress
              : false)
          .toList();

      _promptToSnapshotBloc.add(SelectedDrive(driveId: selectedDriveId));

      // Identify locked drives (private drives without keys in memory)
      final lockedDrives = <String>{};
      if (profileState is ProfileLoggedIn && profileState.user.password.isEmpty) {
        for (final drive in [...userDrives, ...sharedDrives]) {
          // Check if this is a private drive
          if (drive.privacy == DrivePrivacyTag.private) {
            // Check if we have the key in memory
            final driveKey = await _driveDao.getDriveKeyFromMemory(drive.id);
            if (driveKey == null) {
              lockedDrives.add(drive.id);
            }
          }
        }
      }

      // If the selected drive is locked, select a different drive
      if (selectedDriveId != null && lockedDrives.contains(selectedDriveId)) {
        // Find the first available unlocked drive
        final availableDrives = [...userDrives, ...sharedDrives]
            .where((d) => !lockedDrives.contains(d.id))
            .toList();
        
        selectedDriveId = availableDrives.isNotEmpty ? availableDrives.first.id : null;
      }

      emit(
        DrivesLoadSuccess(
          selectedDriveId: selectedDriveId,
          // If the user is not logged in, all drives are considered shared ones.
          userDrives: userDrives,
          sharedDrives: sharedDrives,
          drivesWithAlerts: ghostFolders.map((e) => e.driveId).toList(),
          canCreateNewDrive: _profileCubit.state is ProfileLoggedIn,
          lockedDrives: lockedDrives,
        ),
      );
    });
  }

  void selectDrive(String driveId) {
    final profileIsLoggedIn = _profileCubit.state is ProfileLoggedIn;
    final canCreateNewDrive = profileIsLoggedIn;
    final DrivesState state;
    if (this.state is DrivesLoadSuccess) {
      state = (this.state as DrivesLoadSuccess).copyWith(
        selectedDriveId: driveId,
      );
      _promptToSnapshotBloc.add(SelectedDrive(driveId: driveId));
    } else {
      state = DrivesLoadedWithNoDrivesFound(
        canCreateNewDrive: canCreateNewDrive,
      );
      _promptToSnapshotBloc.add(const SelectedDrive(driveId: null));
    }

    _userPreferencesRepository.saveLastSelectedDriveId(driveId);
    emit(state);
  }

  void cleanDrives() {
    initialSelectedDriveId = null;

    _promptToSnapshotBloc.add(const SelectedDrive(driveId: null));

    final state = DrivesLoadSuccess(
        selectedDriveId: null,
        userDrives: const [],
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: false,
        lockedDrives: const {});

    if (isClosed) {
      return;
    }

    emit(state);
  }

  Future<void> refreshDrives() async {
    // Force a refresh by re-emitting the current state
    // This will trigger the stream listener to re-evaluate locked drives
    final currentState = state;
    if (currentState is DrivesLoadSuccess) {
      emit(DrivesLoadInProgress());
      // The stream subscription will automatically handle the rest
    }
  }

  void _resetDriveSelection(DriveID detachedDriveId) {
    final profileIsLoggedIn = _profileCubit.state is ProfileLoggedIn;
    final canCreateNewDrive = profileIsLoggedIn;
    if (state is DrivesLoadSuccess) {
      final state = this.state as DrivesLoadSuccess;
      state.userDrives.removeWhere((drive) => drive.id == detachedDriveId);
      state.sharedDrives.removeWhere((drive) => drive.id == detachedDriveId);
      final firstOrNullDriveId = state.userDrives.isNotEmpty
          ? state.userDrives.first.id
          : state.sharedDrives.isNotEmpty
              ? state.sharedDrives.first.id
              : null;
      _promptToSnapshotBloc.add(SelectedDrive(
        driveId: firstOrNullDriveId,
      ));
      if (firstOrNullDriveId != null) {
        emit(state.copyWith(selectedDriveId: firstOrNullDriveId));
        return;
      }
    }

    _promptToSnapshotBloc.add(const SelectedDrive(driveId: null));
    emit(DrivesLoadedWithNoDrivesFound(canCreateNewDrive: canCreateNewDrive));
  }

  Future<void> detachDrive(DriveID driveId) async {
    _resetDriveSelection(driveId);
    await Future.delayed(const Duration(seconds: 1));
    await _driveDao.deleteDriveById(driveId: driveId);
  }

  @override
  Future<void> close() {
    _drivesSubscription.cancel();
    return super.close();
  }
}

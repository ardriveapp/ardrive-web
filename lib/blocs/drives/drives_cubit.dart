import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/logger.dart';
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
  final SyncCubit _syncCubit;

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
    required SyncCubit syncCubit,
  })  : _profileCubit = profileCubit,
        _promptToSnapshotBloc = promptToSnapshotBloc,
        _driveDao = driveDao,
        _auth = auth,
        _userPreferencesRepository = userPreferencesRepository,
        _syncCubit = syncCubit,
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

      // An empty table is not the same as an empty account.
      //
      // Drift answers the instant it is asked, and on a login with an empty
      // local database that answer lands long before `updateUserDrives` has
      // said whether the user owns anything. Emitting it as
      // `DrivesLoadSuccess` told the sidebar, the router and the explorer that
      // the user has no drives - as a fact, not as a guess - for the whole
      // length of the fetch. So when the table is empty, wait until the drive
      // list has actually been looked at before answering.
      //
      // Only when it is empty. A returning user whose drives are already local
      // gets the same immediate answer they always did, and never waits.
      if (drives.isEmpty) {
        try {
          await _waitForDriveListRefresh();
        } catch (e, stackTrace) {
          // A wait that could not be completed is no reason to say nothing at
          // all: fall through and answer with what the table holds, which is
          // what this listener did before the wait existed.
          logger.e('Could not wait for the drive list refresh', e, stackTrace);
        }

        if (isClosed) {
          return;
        }

        // The refresh may have written the drives it found. If it did, the
        // watch above has already re-fired with them and that firing owns the
        // answer - this one is holding a snapshot that is now stale, and would
        // report "none found" over the top of it.
        final drivesAfterRefresh = await _driveDao.allDrives().get();

        if (isClosed || drivesAfterRefresh.isNotEmpty) {
          return;
        }
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

      emit(
        DrivesLoadSuccess(
          selectedDriveId: selectedDriveId,
          // If the user is not logged in, all drives are considered shared ones.
          userDrives: userDrives,
          sharedDrives: sharedDrives,
          drivesWithAlerts: ghostFolders.map((e) => e.driveId).toList(),
          canCreateNewDrive: _profileCubit.state is ProfileLoggedIn,
        ),
      );
    });
  }

  /// The single in-flight wait on the drive-list refresh.
  ///
  /// The watch feeding the listener can fire several times while the refresh
  /// is still running - a ghost-folder write or a profile emission is enough -
  /// and every firing runs the listener again without waiting for the last
  /// one, because `Stream.listen` does not await an asynchronous callback.
  /// Left alone each would open its own wait. One shared future keeps that
  /// bounded; and because it stays completed once it completes, a later sync
  /// cannot silence the sidebar again for a user whose drives are now known.
  Future<void>? _driveListRefreshWait;

  Future<void> _waitForDriveListRefresh() =>
      _driveListRefreshWait ??= _syncCubit.waitForDriveListRefresh();

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
        canCreateNewDrive: false);

    if (isClosed) {
      return;
    }

    emit(state);
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

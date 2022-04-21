import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drives_state.dart';

/// [DrivesCubit] includes logic for displaying the drives attached in the app.
/// It works even if the user profile is unavailable.
class DrivesCubit extends Cubit<DrivesState> {
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;

  late StreamSubscription _drivesSubscription;

  DrivesCubit({
    String? initialSelectedDriveId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        super(DrivesLoadInProgress()) {
    _drivesSubscription =
        Rx.combineLatest3<List<Drive>, List<FolderEntry>, void, List<Drive>>(
      _driveDao
          .allDrives(order: OrderBy([OrderingTerm.asc(_driveDao.drives.name)]))
          .watch(),
      _driveDao.ghostFolders().watch(),
      _profileCubit.stream.startWith(ProfileCheckingAvailability()),
      (drives, _, __) => drives,
    ).listen((drives) async {
      final state = this.state;

      String? selectedDriveId;
      if (state is DrivesLoadSuccess && state.selectedDriveId != null) {
        selectedDriveId = state.selectedDriveId;
      } else {
        selectedDriveId = initialSelectedDriveId ??
            (drives.isNotEmpty ? drives.first.id : null);
      }

      final profile = _profileCubit.state;

      final walletAddress =
          profile is ProfileLoggedIn ? profile.walletAddress : null;

      final ghostFolders = await _driveDao.ghostFolders().get();
      emit(
        DrivesLoadSuccess(
          selectedDriveId: selectedDriveId,
          // If the user is not logged in, all drives are considered shared ones.
          userDrives: drives
              .where((d) => profile is ProfileLoggedIn
                  ? d.ownerAddress == walletAddress
                  : false)
              .toList(),
          sharedDrives: drives
              .where((d) => profile is ProfileLoggedIn
                  ? d.ownerAddress != walletAddress
                  : true)
              .toList(),
          drivesWithAlerts: ghostFolders.map((e) => e.driveId).toList(),
          canCreateNewDrive: _profileCubit.state is ProfileLoggedIn,
        ),
      );
    });
  }

  void selectDrive(String driveId) {
    final canCreateNewDrive = _profileCubit.state is ProfileLoggedIn;
    final state = this.state is DrivesLoadSuccess
        ? (this.state as DrivesLoadSuccess).copyWith(selectedDriveId: driveId)
        : DrivesLoadSuccess(
            selectedDriveId: driveId,
            userDrives: [],
            sharedDrives: [],
            drivesWithAlerts: [],
            canCreateNewDrive: canCreateNewDrive);
    emit(state);
  }

  @override
  Future<void> close() {
    _drivesSubscription.cancel();
    return super.close();
  }
}

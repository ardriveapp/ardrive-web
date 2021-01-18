import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drives_state.dart';

/// [DrivesCubit] includes logic for displaying the drives attached in the app.
/// It works even if the user profile is unavailable.
class DrivesCubit extends Cubit<DrivesState> {
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;

  StreamSubscription _drivesSubscription;

  DrivesCubit({
    String initialSelectedDriveId,
    @required ProfileCubit profileCubit,
    @required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        super(DrivesLoadInProgress()) {
    _drivesSubscription = Rx.combineLatest2<List<Drive>, void, List<Drive>>(
      _driveDao
          .allDrives(order: OrderBy([OrderingTerm.asc(_driveDao.drives.name)]))
          .watch(),
      _profileCubit.startWith(null),
      (drives, _) => drives,
    ).listen((drives) {
      final state = this.state;

      String selectedDriveId;
      if (state is DrivesLoadSuccess && state.selectedDriveId != null) {
        selectedDriveId = state.selectedDriveId;
      } else {
        selectedDriveId = initialSelectedDriveId ??
            (drives.isNotEmpty ? drives.first.id : null);
      }

      final profile = _profileCubit.state;

      emit(
        DrivesLoadSuccess(
          selectedDriveId: selectedDriveId,
          // If the user is not logged in, all drives are considered shared ones.
          userDrives: drives
              .where((d) => profile is ProfileLoggedIn
                  ? d.ownerAddress == profile.wallet.address
                  : false)
              .toList(),
          sharedDrives: drives
              .where((d) => profile is ProfileLoggedIn
                  ? d.ownerAddress != profile.wallet.address
                  : true)
              .toList(),
          canCreateNewDrive: _profileCubit.state is ProfileLoggedIn,
        ),
      );
    });
  }

  void selectDrive(String driveId) {
    final state = this.state as DrivesLoadSuccess;
    emit(state.copyWith(selectedDriveId: driveId));
  }

  @override
  Future<void> close() {
    _drivesSubscription.cancel();
    return super.close();
  }
}

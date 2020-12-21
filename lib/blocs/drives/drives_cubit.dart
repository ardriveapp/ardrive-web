import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drives_state.dart';

class DrivesCubit extends Cubit<DrivesState> {
  final ProfileCubit _profileCubit;
  final DrivesDao _drivesDao;

  StreamSubscription _drivesSubscription;

  DrivesCubit({
    String initialSelectedDriveId,
    @required ProfileCubit profileCubit,
    @required DrivesDao drivesDao,
  })  : _profileCubit = profileCubit,
        _drivesDao = drivesDao,
        super(DrivesLoadInProgress()) {
    _drivesSubscription = Rx.combineLatest2<List<Drive>, void, List<Drive>>(
      _drivesDao.watchAllDrives(),
      _profileCubit.startWith(null),
      (drives, _) => drives,
    ).listen((drives) {
      final state = this.state;
      final profile = _profileCubit.state as ProfileLoggedIn;

      String selectedDriveId;
      if (state is DrivesLoadSuccess && state.selectedDriveId != null) {
        selectedDriveId = state.selectedDriveId;
      } else {
        selectedDriveId = drives.isNotEmpty
            ? (initialSelectedDriveId ?? drives.first.id)
            : null;
      }

      emit(
        DrivesLoadSuccess(
          selectedDriveId: selectedDriveId,
          userDrives: drives
              .where((d) => d.ownerAddress == profile.wallet.address)
              .toList(),
          sharedDrives: drives
              .where((d) => d.ownerAddress != profile.wallet.address)
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

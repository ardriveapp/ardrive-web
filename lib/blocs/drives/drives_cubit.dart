import 'dart:async';

import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'drives_state.dart';

class DrivesCubit extends Cubit<DrivesState> {
  final ProfileBloc _profileBloc;
  final DrivesDao _drivesDao;

  StreamSubscription _drivesSubscription;

  DrivesCubit({ProfileBloc profileBloc, DrivesDao drivesDao})
      : _profileBloc = profileBloc,
        _drivesDao = drivesDao,
        super(DrivesLoadInProgress()) {
    _drivesSubscription = Rx.combineLatest2<List<Drive>, void, List<Drive>>(
      _drivesDao.watchAllDrives(),
      _profileBloc.startWith(null),
      (drives, _) => drives,
    ).listen((drives) {
      final state = this.state;
      final profile = _profileBloc.state as ProfileLoaded;

      String selectedDriveId;
      if (state is DrivesLoadSuccess && state.selectedDriveId != null) {
        selectedDriveId = state.selectedDriveId;
      } else {
        selectedDriveId = drives.isNotEmpty ? drives.first.id : null;
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
          canCreateNewDrive: _profileBloc.state is ProfileLoaded,
        ),
      );
    });
  }

  void selectDrive(String driveId) {
    final state = this.state;
    if (state is DrivesLoadSuccess) {
      emit(state.copyWith(selectedDriveId: driveId));
    }
  }

  @override
  Future<void> close() {
    _drivesSubscription.cancel();
    return super.close();
  }
}

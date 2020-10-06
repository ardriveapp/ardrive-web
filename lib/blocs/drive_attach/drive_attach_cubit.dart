import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'drive_attach_state.dart';

class DriveAttachCubit extends Cubit<DriveAttachState> {
  final form = FormGroup({
    'driveId': FormControl(validators: [Validators.required]),
    'name': FormControl(validators: [Validators.required]),
  });

  final ArweaveService _arweave;
  final DrivesDao _drivesDao;
  final SyncBloc _syncBloc;
  final DrivesCubit _drivesBloc;
  final ProfileBloc _profileBloc;

  DriveAttachCubit({
    @required ArweaveService arweave,
    @required DrivesDao drivesDao,
    @required SyncBloc syncBloc,
    @required DrivesCubit drivesBloc,
    @required ProfileBloc profileBloc,
  })  : _arweave = arweave,
        _drivesDao = drivesDao,
        _syncBloc = syncBloc,
        _drivesBloc = drivesBloc,
        _profileBloc = profileBloc,
        super(DriveAttachInitial());

  void submit() async {
    if (form.invalid) {
      return;
    }

    emit(DriveAttachInProgress());

    final profile = _profileBloc.state as ProfileLoaded;
    final driveId = form.control('driveId').value;
    final driveName = form.control('name').value;

    final driveEntity = await _arweave.tryGetFirstDriveEntityWithId(driveId);

    if (driveEntity == null) {
      form.control('driveId').setErrors({'drive-not-found': true});
      emit(DriveAttachInitial());
      return;
    }

    await _drivesDao.attachDrive(
      name: driveName,
      entity: driveEntity,
      profileKey: profile.cipherKey,
    );

    _syncBloc.add(SyncWithNetwork());
    _drivesBloc.selectDrive(driveId);

    emit(DriveAttachSuccessful());
  }
}

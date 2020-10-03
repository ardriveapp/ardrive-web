import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
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
  final DrivesBloc _drivesBloc;
  final ProfileBloc _profileBloc;

  DriveAttachCubit({
    ArweaveService arweave,
    DrivesDao drivesDao,
    SyncBloc syncBloc,
    DrivesBloc drivesBloc,
    ProfileBloc profileBloc,
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

    final driveKey =
        await deriveDriveKey(profile.wallet, driveId, profile.password);

    final driveEntity = await _arweave.getDriveEntity(driveId, driveKey);

    await _drivesDao.attachDrive(
      name: driveName,
      entity: driveEntity,
      driveKey: driveKey,
      profileKey: profile.cipherKey,
    );

    _syncBloc.add(SyncWithNetwork());
    _drivesBloc.add(SelectDrive(driveId));

    emit(DriveAttachSuccessful());
  }
}

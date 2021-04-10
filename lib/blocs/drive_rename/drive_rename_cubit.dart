import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'drive_rename_state.dart';

class DriveRenameCubit extends Cubit<DriveRenameState> {
  FormGroup form;

  final String driveId;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;

  DriveRenameCubit({
    @required this.driveId,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
    @required ProfileCubit profileCubit,
    @required SyncCubit syncCubit,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        super(DriveRenameInitial()) {
    form = FormGroup({
      'name': FormControl<String>(
        validators: [
          Validators.required,
          Validators.pattern(kFolderNameRegex),
          Validators.pattern(kTrimTrailingRegex),
        ],
        asyncValidators: [
          _uniqueDriveName,
        ],
      ),
    });

    () async {
      final name = await _driveDao
          .driveById(driveId: driveId)
          .map((f) => f.name)
          .getSingle();
      form.control('name').value = name;
      emit(DriveRenameInitial());
    }();
  }

  Future<void> submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }

    try {
      final newName = form.control('name').value.toString().trim();
      final profile = _profileCubit.state as ProfileLoggedIn;
      final driveKey = await _driveDao.getDriveKey(driveId, profile.cipherKey);

      emit(DriveRenameInProgress());

      await _driveDao.transaction(() async {
        var drive = await _driveDao.driveById(driveId: driveId).getSingle();
        drive = drive.copyWith(name: newName, lastUpdated: DateTime.now());

        final driveEntity = drive.asEntity();

        final driveTx = await _arweave.prepareEntityTx(
            driveEntity, profile.wallet, driveKey);

        await _arweave.postTx(driveTx);
        await _driveDao.writeToDrive(drive);

        driveEntity.ownerAddress = profile.walletAddress;
        driveEntity.txId = driveTx.id;

        await _driveDao.insertDriveRevision(driveEntity.toRevisionCompanion(
            performedAction: RevisionAction.rename));
      });

      emit(DriveRenameSuccess());
    } catch (err) {
      addError(err);
    }
  }

  Future<Map<String, dynamic>> _uniqueDriveName(
      AbstractControl<dynamic> control) async {
    final drive = await _driveDao.driveById(driveId: driveId).getSingle();
    final String newDriveName = control.value;

    if (newDriveName == drive.name) {
      return null;
    }

    // Check that the current drive does not already have a drive with the target file name.
    final drivesWithName = (await _driveDao.allDrives().get())
        .where((element) => element.name == newDriveName);
    final nameAlreadyExists = drivesWithName.isNotEmpty;

    if (nameAlreadyExists) {
      control.markAsTouched();
      return {AppValidationMessage.driveNameAlreadyPresent: true};
    }

    return null;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(DriveRenameFailure());

    super.onError(error, stackTrace);
  }
}

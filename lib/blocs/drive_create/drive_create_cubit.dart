import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'drive_create_state.dart';

class DriveCreateCubit extends Cubit<DriveCreateState> {
  final form = FormGroup({
    'name': FormControl(
      validators: [
        Validators.required,
        Validators.pattern(kDriveNameRegex),
      ],
    ),
    'privacy': FormControl(
        value: DrivePrivacy.private, validators: [Validators.required]),
  });

  final ArweaveService _arweave;
  final DrivesDao _drivesDao;
  final ProfileCubit _profileCubit;
  final DrivesCubit _drivesCubit;

  DriveCreateCubit({
    @required ArweaveService arweave,
    @required DrivesDao drivesDao,
    @required ProfileCubit profileCubit,
    @required DrivesCubit drivesCubit,
  })  : _arweave = arweave,
        _drivesDao = drivesDao,
        _profileCubit = profileCubit,
        _drivesCubit = drivesCubit,
        super(DriveCreateInitial());

  Future<void> submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }

    emit(DriveCreateInProgress());

    try {
      final String driveName = form.control('name').value;
      final String drivePrivacy = form.control('privacy').value;

      final profile = _profileCubit.state as ProfileLoaded;
      final wallet = profile.wallet;

      final createRes = await _drivesDao.createDrive(
        name: driveName,
        ownerAddress: wallet.address,
        privacy: drivePrivacy,
        wallet: wallet,
        password: profile.password,
        profileKey: profile.cipherKey,
      );

      final drive = DriveEntity(
        id: createRes.driveId,
        name: driveName,
        rootFolderId: createRes.rootFolderId,
        privacy: drivePrivacy,
        authMode: drivePrivacy == DrivePrivacy.private
            ? DriveAuthMode.password
            : null,
      );

      final driveDataItem = await _arweave.prepareEntityDataItem(
          drive, wallet, createRes.driveKey);

      final rootFolderDataItem = await _arweave.prepareEntityDataItem(
        FolderEntity(
          id: drive.rootFolderId,
          driveId: drive.id,
          name: driveName,
        ),
        wallet,
        createRes.driveKey,
      );

      final createTx = await _arweave.prepareDataBundleTx(
          DataBundle(items: [driveDataItem, rootFolderDataItem]), wallet);

      await _arweave.postTx(createTx);

      _drivesCubit.selectDrive(drive.id);
    } catch (err) {
      addError(err);
    }

    emit(DriveCreateSuccess());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(DriveCreateFailure());
    super.onError(error, stackTrace);
  }
}

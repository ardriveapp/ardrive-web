import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
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
        Validators.pattern(kTrimTrailingRegex),
      ],
    ),
    'privacy': FormControl(
        value: DrivePrivacy.private, validators: [Validators.required]),
  });

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final DrivesCubit _drivesCubit;

  DriveCreateCubit({
    @required ArweaveService arweave,
    @required DriveDao driveDao,
    @required ProfileCubit profileCubit,
    @required DrivesCubit drivesCubit,
  })  : _arweave = arweave,
        _driveDao = driveDao,
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
      final driveName = form.control('name').value.toString().trim();
      final String drivePrivacy = form.control('privacy').value;

      final profile = _profileCubit.state as ProfileLoggedIn;
      final walletAddress = await profile.getWalletAddress();
      final createRes = await _driveDao.createDrive(
        name: driveName,
        ownerAddress: walletAddress,
        privacy: drivePrivacy,
        getWalletSignature: profile.getRawWalletSignature,
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

      // TODO: Revert back to using data bundles when the api is stable again.
      final owner = await profile.getWalletOwner();
      final driveTx = await _arweave.prepareEntityTx(
          drive, profile.getRawWalletSignature, owner, createRes.driveKey);

      final rootFolderEntity = FolderEntity(
        id: drive.rootFolderId,
        driveId: drive.id,
        name: driveName,
      );

      final rootFolderTx = await _arweave.prepareEntityTx(
        rootFolderEntity,
        profile.getRawWalletSignature,
        owner,
        createRes.driveKey,
      );

      await _arweave.postTx(driveTx);
      await _arweave.postTx(rootFolderTx);
      print(driveTx.id);
      print(rootFolderTx.id);
      rootFolderEntity.txId = rootFolderTx.id;
      await _driveDao.insertFolderRevision(rootFolderEntity.toRevisionCompanion(
          performedAction: RevisionAction.create));

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

    print('Failed to create drive: $error $stackTrace');
  }
}

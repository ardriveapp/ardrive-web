import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/utils.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'drive_attach_state.dart';

/// [DriveAttachCubit] includes logic for attaching drives to the user's profile.
class DriveAttachCubit extends Cubit<DriveAttachState> {
  late FormGroup form;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final SyncCubit _syncBloc;
  final DrivesCubit _drivesBloc;
  final SecretKey? _profileKey;

  late SecretKey? _driveKey;

  DriveAttachCubit({
    DriveID? initialDriveId,
    String? initialDriveName,
    SecretKey? initialDriveKey,
    SecretKey? profileKey,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required SyncCubit syncBloc,
    required DrivesCubit drivesBloc,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _syncBloc = syncBloc,
        _drivesBloc = drivesBloc,
        _profileKey = profileKey,
        super(DriveAttachInitial()) {
    initializeForm(
      driveId: initialDriveId,
      driveName: initialDriveName,
      driveKey: initialDriveKey,
    );
  }

  Future<void> cleanUpKeylessDrives() async =>
      await _driveDao.deleteAllKeylessPrivateDrives();

  Future<void> initializeForm({
    String? driveId,
    String? driveName,
    SecretKey? driveKey,
  }) async {
    _driveKey = driveKey;
    form = FormGroup(
      {
        'driveId': FormControl<String>(
          validators: [Validators.required],
          asyncValidators: [_drivePrivacyLoader, _driveNameLoader],
          // Debounce drive name loading by 500ms.
          asyncValidatorsDebounceTime: 500,
        ),
        'name': FormControl<String>(
          validators: [
            Validators.required,
            Validators.pattern(kDriveNameRegex),
            Validators.pattern(kTrimTrailingRegex),
          ],
        ),
      },
    );

    // Add the initial drive id in a microtask to properly trigger the drive name loader.
    await Future.microtask(() {
      if (driveId != null) {
        form.control('driveId').updateValue(driveId);
      }
    });

    if (driveName != null && driveName.isNotEmpty) {
      form.control('name').updateValue(driveName);
      submit();
    }
  }

  void submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }
    await cleanUpKeylessDrives();
    emit(DriveAttachInProgress());

    try {
      final String driveId = form.control('driveId').value;
      final driveName = form.control('name').value.toString().trim();
      final driveKey = await getDriveKey();
      final driveEntity = await _arweave.getLatestDriveEntityWithId(
        driveId,
        driveKey,
      );
      if (driveEntity == null) {
        form
            .control('driveId')
            .setErrors({AppValidationMessage.driveAttachDriveNotFound: true});
        emit(DriveAttachInitial());
        return;
      }

      await _driveDao.writeDriveEntity(
        name: driveName,
        entity: driveEntity,
        driveKey: driveKey,
        profileKey: _profileKey,
      );

      _drivesBloc.selectDrive(driveId);
      emit(DriveAttachSuccess());
      unawaited(_syncBloc.startSync());
    } catch (err) {
      addError(err);
    }
  }

  Future<SecretKey?> getDriveKey() async {
    if (_driveKey != null) {
      return _driveKey;
    }
    final String? driveKeyBase64 = form.controls.containsKey('driveKey')
        ? form.control('driveKey').value
        : null;
    SecretKey? driveKey;
    if (driveKeyBase64 != null) {
      try {
        driveKey = SecretKey(decodeBase64ToBytes(driveKeyBase64));
      } catch (e) {
        form.control('driveKey').setErrors({
          AppValidationMessage.driveAttachInvalidDriveKey: true,
        });
        return null;
      }
    }
    return driveKey;
  }

  Future<Map<String, dynamic>?> _driveNameLoader(
      AbstractControl<dynamic> driveIdControl) async {
    if ((driveIdControl as AbstractControl<String?>).isNull) {
      return null;
    }

    final driveId = driveIdControl.value;
    if (driveId == null) {
      return null;
    }

    final driveKey = await getDriveKey();

    final drive = await _arweave.getLatestDriveEntityWithId(driveId, driveKey);

    if (drive == null) {
      if (driveKey != null) {
        form.control('driveKey').markAsTouched();
        return {AppValidationMessage.driveAttachInvalidDriveKey: true};
      }
      return null;
    }

    form.control('name').updateValue(drive.name);

    return null;
  }

  Future<Map<String, dynamic>?> _driveKeyValidator(
      AbstractControl<dynamic> driveKeyControl) async {
    final driveId = form.control('driveId').value;

    if (driveId == null) {
      return null;
    }

    final driveKey = await getDriveKey();

    final drive = await _arweave.getLatestDriveEntityWithId(driveId, driveKey);

    if (drive == null) {
      driveKeyControl.markAsTouched();
      return {AppValidationMessage.driveAttachInvalidDriveKey: true};
    }

    form.control('name').updateValue(drive.name);

    return null;
  }

  Future<Map<String, dynamic>?> _drivePrivacyLoader(
      AbstractControl<dynamic> driveIdControl) async {
    if ((driveIdControl as AbstractControl<String?>).isNull) {
      return null;
    }

    final driveId = driveIdControl.value;
    if (driveId == null) {
      return null;
    }
    final drivePrivacy = await _arweave.getDrivePrivacyForId(driveId);

    switch (drivePrivacy) {
      case DrivePrivacy.private:
        emit(DriveAttachPrivate());
        form.addAll({
          'driveKey': FormControl<String>(
            validators: [
              Validators.required,
            ],
            asyncValidatorsDebounceTime: 1000,
            asyncValidators: [_driveKeyValidator],
          ),
        });

        break;
      case null:
        emit(DriveAttachDriveNotFound());
        break;
      default:
        return null;
    }

    return null;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(DriveAttachFailure());
    super.onError(error, stackTrace);

    print('Failed to attach drive: $error $stackTrace');
  }
}

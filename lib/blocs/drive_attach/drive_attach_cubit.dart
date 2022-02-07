import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
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
  final ProfileCubit _profileCubit;

  final SecretKey? _initialDriveKey;

  DriveAttachCubit({
    String? initialDriveId,
    String? driveName,
    SecretKey? sharedDriveKey,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required SyncCubit syncBloc,
    required DrivesCubit drivesBloc,
    required ProfileCubit profileCubit,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _syncBloc = syncBloc,
        _drivesBloc = drivesBloc,
        _profileCubit = profileCubit,
        _initialDriveKey = sharedDriveKey,
        super(DriveAttachInitial()) {
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
    Future.microtask(() {
      if (initialDriveId != null) {
        form.control('driveId').updateValue(initialDriveId);
      }
    });
    if (driveName != null && driveName.isNotEmpty) {
      form.control('driveId').value = initialDriveId;
      form.control('name').value = driveName;
      submit();
    }
  }

  void submit() async {
    form.markAllAsTouched();

    if (form.invalid ||
        (_profileCubit.state is! ProfileLoggedIn && _initialDriveKey != null)) {
      emit(DriveAttachFailure());
      return;
    }

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
        emit(DriveAttachFailure());
        return;
      }

      await _driveDao.writeDriveEntity(
        name: driveName,
        entity: driveEntity,
        driveKey: driveKey,
        profileKey: (_profileCubit.state as ProfileLoggedIn).cipherKey,
      );

      _drivesBloc.selectDrive(driveId);
      emit(DriveAttachSuccess());
      unawaited(_syncBloc.startSync());
    } catch (err) {
      addError(err);
    }
  }

  Future<SecretKey?> getDriveKey() async {
    final String? driveKeyBytes = form.controls.containsKey('driveKey')
        ? form.control('driveKey').value
        : null;
    var driveKey = _initialDriveKey;
    if (driveKeyBytes != null) {
      try {
        driveKey = SecretKey(decodeBase64ToBytes(driveKeyBytes));
      } catch (e) {
        form.control('driveKey').setErrors({
          AppValidationMessage.driveAttachInvalidDriveKey: true,
        });
        emit(DriveAttachFailure());
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
    SecretKey? driveKey;
    if (form.controls.containsKey('driveKey')) {
      driveKey = await getDriveKey();
    }
    final drive = await _arweave.getLatestDriveEntityWithId(driveId, driveKey);

    if (drive == null) {
      return null;
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
            asyncValidators: [_driveNameLoader],
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

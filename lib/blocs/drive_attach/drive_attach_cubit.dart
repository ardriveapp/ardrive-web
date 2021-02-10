import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'drive_attach_state.dart';

/// [DriveAttachCubit] includes logic for attaching drives to the user's profile.
class DriveAttachCubit extends Cubit<DriveAttachState> {
  FormGroup form;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final SyncCubit _syncBloc;
  final DrivesCubit _drivesBloc;

  DriveAttachCubit({
    String initialDriveId,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
    @required SyncCubit syncBloc,
    @required DrivesCubit drivesBloc,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _syncBloc = syncBloc,
        _drivesBloc = drivesBloc,
        super(DriveAttachInitial()) {
    form = FormGroup(
      {
        'driveId': FormControl<String>(
          validators: [Validators.required],
          asyncValidators: [_driveNameLoader],
          // Debounce drive name loading by 500ms.
          asyncValidatorsDebounceTime: 500,
        ),
        'name': FormControl<String>(
          validators: [
            Validators.required,
            Validators.pattern(kDriveNameRegex),
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
  }

  void submit({String autoDriveId, String autoDriveName}) async {
    if ((autoDriveId == null) && (autoDriveName == null)) {
      form.markAllAsTouched();

      if (form.invalid) {
        return;
      }
    }

    emit(DriveAttachInProgress());

    try {
      final String driveId = autoDriveId ?? form.control('driveId').value;
      final driveName =
          autoDriveName ?? form.control('name').value.toString().trim();

      final driveEntity = await _arweave.getLatestDriveEntityWithId(driveId);
      if ((autoDriveId == null) && (autoDriveName == null)) {
        if (driveEntity == null) {
          form
              .control('driveId')
              .setErrors({AppValidationMessage.driveNotFound: true});
          emit(DriveAttachFailure());
          return;
        }
      }

      await _driveDao.writeDriveEntity(name: driveName, entity: driveEntity);

      _drivesBloc.selectDrive(driveId);
      unawaited(_syncBloc.startSync());
    } catch (err) {
      addError(err);
    }

    emit(DriveAttachSuccess());
  }

  Future<Map<String, dynamic>> _driveNameLoader(
      AbstractControl<dynamic> driveIdControl) async {
    if ((driveIdControl as AbstractControl<String>).isNullOrEmpty) {
      return null;
    }

    final String driveId = driveIdControl.value;
    final drive = await _arweave.getLatestDriveEntityWithId(driveId);

    if (drive == null) {
      return null;
    }

    form.control('name').updateValue(drive.name);

    return null;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(DriveAttachFailure());
    print(stackTrace);
    super.onError(error, stackTrace);
  }
}

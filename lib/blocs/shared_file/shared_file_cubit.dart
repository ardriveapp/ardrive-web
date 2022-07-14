import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/utils.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'shared_file_state.dart';

/// [SharedFileCubit] includes logic for displaying a file shared with another user.
class SharedFileCubit extends Cubit<SharedFileState> {
  late FormGroup form;

  final String fileId;

  /// The [SecretKey] that can be used to decode the target file.
  ///
  /// `null` if the file is public.
  final SecretKey? fileKey;

  final ArweaveService _arweave;

  SharedFileCubit({required this.fileId, this.fileKey, required arweave})
      : _arweave = arweave,
        super(SharedFileLoadInProgress()) {
    loadFileDetails();
    initializeForm();
  }

  Future<void> initializeForm() async {
    form = FormGroup(
      {
        'fileKey': FormControl<String>(
          validators: [
            Validators.required,
          ],
          asyncValidatorsDebounceTime: 500,
          asyncValidators: [_fileKeyValidator],
        ),
      },
    );
  }

  Future<Map<String, dynamic>?> _fileKeyValidator(
    AbstractControl<dynamic> fileKeyControl,
  ) async {
    try {
      SecretKey(decodeBase64ToBytes(fileKeyControl.value));
    } catch (_) {
      fileKeyControl.markAsTouched();
      return {AppValidationMessage.sharedFileInvalidFileKey: true};
    }
    return null;
  }

  Future<void> loadFileDetails() async {
    emit(SharedFileLoadInProgress());
    final privacy = await _arweave.getFilePrivacyForId(fileId);
    if (fileKey == null && privacy == DrivePrivacy.private) {
      emit(SharedFileIsPrivate());
    } else {
      final file = await _arweave.getLatestFileEntityWithId(fileId, fileKey);

      if (file != null) {
        emit(SharedFileLoadSuccess(file: file, fileKey: fileKey));
      } else {
        emit(SharedFileNotFound());
      }
    }
  }

  void submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }

    emit(SharedFileLoadInProgress());
    final String? fileKeyBase64 = form.control('fileKey').value;
    final fileKey = SecretKey(decodeBase64ToBytes(fileKeyBase64!));
    final file = await _arweave.getLatestFileEntityWithId(fileId, fileKey);

    if (file != null) {
      emit(SharedFileLoadSuccess(file: file, fileKey: fileKey));
    } else {
      emit(SharedFileNotFound());
    }
  }
}

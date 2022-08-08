import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
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

  SharedFileCubit({
    required this.fileId,
    this.fileKey,
    required arweave,
  })  : _arweave = arweave,
        super(SharedFileLoadInProgress()) {
    loadFileDetails(fileKey);
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
      return {AppValidationMessage.sharedFileIncorrectFileKey: true};
    }
    return null;
  }

  String getPerformedRevisionAction(FileEntity entity,
      [FileRevision? previousRevision]) {
    if (previousRevision != null) {
      if (entity.name != previousRevision.name) {
        return RevisionAction.rename;
      } else if (entity.parentFolderId != previousRevision.parentFolderId) {
        return RevisionAction.move;
      } else if (entity.dataTxId != previousRevision.dataTxId) {
        return RevisionAction.uploadNewVersion;
      }
    }

    return RevisionAction.create;
  }

  Future<List<FileRevision>> computeRevisionsFromEntities(
    List<FileEntity> fileEntities,
  ) async {
    late FileRevision oldestRevision;

    fileEntities.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    oldestRevision = fileEntities.first.toRevision(
      performedAction: RevisionAction.create,
    );
    fileEntities.removeAt(0);
    final revisions = <FileRevision>[oldestRevision];
    for (final entity in fileEntities) {
      final revisionPerformedAction = getPerformedRevisionAction(
        entity,
        revisions.last,
      );

      entity.parentFolderId = entity.parentFolderId ?? rootPath;
      final revision = entity.toRevision(
        performedAction: revisionPerformedAction,
      );

      if (revision.action.isEmpty) {
        continue;
      }

      revisions.add(revision);
    }

    return revisions;
  }

  Future<void> loadFileDetails(SecretKey? fileKey) async {
    emit(SharedFileLoadInProgress());
    final privacy = await _arweave.getFilePrivacyForId(fileId);
    if (fileKey == null && privacy == DrivePrivacy.private) {
      emit(SharedFileIsPrivate());
      return;
    }
    final allEntities = await _arweave.getAllFileEntitiesWithId(
      fileId,
      fileKey,
    );
    if (allEntities != null) {
      {
        final revisions = await computeRevisionsFromEntities(allEntities);

        emit(SharedFileLoadSuccess(fileRevisions: revisions, fileKey: fileKey));
        return;
      }
    }
    emit(SharedFileNotFound());
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
      loadFileDetails(fileKey);
    } else {
      emit(SharedFileIsPrivate());
      form
          .control('fileKey')
          .setErrors({AppValidationMessage.sharedFileIncorrectFileKey: true});
    }
  }
}

import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart' show FileEntity;
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart';
import 'package:retry/retry.dart';
import 'package:uuid/uuid.dart';

part 'file_id_resolver.dart';
part 'pin_file_event.dart';
part 'pin_file_state.dart';
part 'types.dart';

class PinFileBloc extends Bloc<PinFileEvent, PinFileState> {
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final TurboUploadService _turboUploadService;
  final ProfileCubit _profileCubit;
  final FileIdResolver _fileIdResolver;
  final ArDriveCrypto _crypto;

  final nameTextController = TextEditingController();
  final DriveID _driveId;
  final FolderID _parentFolderId;

  PinFileBloc({
    required ArweaveService arweave,
    required DriveDao driveDao,
    required TurboUploadService turboUploadService,
    required ProfileCubit profileCubit,
    required FileIdResolver fileIdResolver,
    required DriveID driveID,
    required FolderID parentFolderId,
    required ArDriveCrypto crypto,
  })  : _fileIdResolver = fileIdResolver,
        _arweave = arweave,
        _driveDao = driveDao,
        _turboUploadService = turboUploadService,
        _profileCubit = profileCubit,
        _driveId = driveID,
        _parentFolderId = parentFolderId,
        _crypto = crypto,
        super(const PinFileInitial()) {
    nameTextController.text = '';

    on<FieldsChanged>(_handleFieldsChanged);
    on<PinFileCancel>(_handlePinFileCancel);
    on<PinFileSubmit>(_handlePinFileSubmit);
  }

  Future<void> _handleFieldsChanged(
    FieldsChanged event,
    Emitter<PinFileState> emit,
  ) async {
    String name = event.name;
    final String id = event.id;

    if (name.isEmpty && id.isEmpty) {
      emit(const PinFileInitial());
      return;
    }

    final stateId = state.id;
    final hasIdChanged = stateId != id;

    // FIXME: may throw, catch error
    SynchronousValidationResult syncValidationResult =
        await _runSynchronousValidation(name, id);

    if (hasIdChanged && syncValidationResult.isIdValid) {
      emit(PinFileNetworkCheckRunning(
        id: id,
        name: name,
        idValidation: syncValidationResult.idValidation,
        nameValidation: syncValidationResult.nameValidation,
      ));

      try {
        final fileInfo = await _runNetworkValidation(
          id,
          name,
          syncValidationResult.idValidation,
        );

        // do not override the name if it's already set
        final newName = name.isEmpty ? (fileInfo.maybeName ?? '') : name;
        if (newName != name) {
          logger.d(
            'name changed from $name to $newName - name in state: '
            '${state.name}',
          );
          nameTextController.text = newName;
          name = newName;
        }

        // FIXME: may throw, catch error
        syncValidationResult = await _runSynchronousValidation(name, id);

        emit(PinFileFieldsValid(
          id: id,
          name: name,
          nameValidation: syncValidationResult.nameValidation,
          idValidation: syncValidationResult.idValidation,
          privacy: fileInfo.privacy,
          dataContentType: fileInfo.dataContentType,
          maybeLastUpdated: fileInfo.maybeLastUpdated,
          maybeLastModified: fileInfo.maybeLastModified,
          dateCreated: fileInfo.dateCreated,
          size: fileInfo.size,
          dataTxId: fileInfo.dataTxId,
          pinnedDataOwnerAddress: fileInfo.pinnedDataOwnerAddress,
        ));
      } catch (err) {
        if (err is FileIdResolverException) {
          final cancelled = err.cancelled;

          if (!cancelled) {
            emit(
              PinFileFieldsValidationError(
                id: id,
                name: name,
                nameValidation: syncValidationResult.nameValidation,
                idValidation: syncValidationResult.idValidation,
                cancelled: cancelled,
                networkError: err.networkError,
                isArFsEntityValid: err.isArFsEntityValid,
                isArFsEntityPublic: err.isArFsEntityPublic,
                doesDataTransactionExist: err.doesDataTransactionExist,
              ),
            );
          } else {
            logger.d('PinFileNetworkCheck cancelled');
          }
        } else {
          logger.e('unknown error in PinFileNetworkCheck');
          rethrow;
        }
      }
    }

    if (!syncValidationResult.isIdValid) {
      if (state is PinFileFieldsValidationError) {
        final stateAsPinFileFieldsValidationError =
            state as PinFileFieldsValidationError;
        emit(PinFileFieldsValidationError(
          id: id,
          name: name,
          nameValidation: syncValidationResult.nameValidation,
          idValidation: syncValidationResult.idValidation,
          cancelled: stateAsPinFileFieldsValidationError.cancelled,
          networkError: stateAsPinFileFieldsValidationError.networkError,
          isArFsEntityValid:
              stateAsPinFileFieldsValidationError.isArFsEntityValid,
          isArFsEntityPublic:
              stateAsPinFileFieldsValidationError.isArFsEntityPublic,
          doesDataTransactionExist:
              stateAsPinFileFieldsValidationError.doesDataTransactionExist,
        ));
      } else if (state is PinFileNetworkCheckRunning) {
        emit(PinFileNetworkCheckRunning(
          id: id,
          name: name,
          nameValidation: syncValidationResult.nameValidation,
          idValidation: syncValidationResult.idValidation,
        ));
      } else if (state is PinFileFieldsValid) {
        emit(
          PinFileFieldsValidationError(
            id: id,
            name: name,
            nameValidation: syncValidationResult.nameValidation,
            idValidation: syncValidationResult.idValidation,
            cancelled: false,
            networkError: false,
            isArFsEntityValid: true,
            isArFsEntityPublic: true,
            doesDataTransactionExist: true,
          ),
        );
      } else if (state is PinFileInitial) {
        emit(
          PinFileFieldsValidationError(
            id: id,
            name: name,
            nameValidation: syncValidationResult.nameValidation,
            idValidation: syncValidationResult.idValidation,
            cancelled: false,
            networkError: false,
            isArFsEntityValid: true,
            isArFsEntityPublic: true,
            doesDataTransactionExist: true,
          ),
        );
      } else {
        logger.d('Unexpected state $state');
      }
    } else {
      if (state is PinFileFieldsValid) {
        final stateAsPinFileFieldsValid = state as PinFileFieldsValid;
        emit(
          PinFileFieldsValid(
            id: id,
            name: name,
            nameValidation: syncValidationResult.nameValidation,
            idValidation: stateAsPinFileFieldsValid.idValidation,
            privacy: stateAsPinFileFieldsValid.privacy,
            dataContentType: stateAsPinFileFieldsValid.dataContentType,
            dateCreated: stateAsPinFileFieldsValid.dateCreated,
            size: stateAsPinFileFieldsValid.size,
            dataTxId: stateAsPinFileFieldsValid.dataTxId,
            maybeLastUpdated: stateAsPinFileFieldsValid.maybeLastUpdated,
            maybeLastModified: stateAsPinFileFieldsValid.maybeLastModified,
            pinnedDataOwnerAddress:
                stateAsPinFileFieldsValid.pinnedDataOwnerAddress,
          ),
        );
      } else if (state is PinFileNetworkCheckRunning) {
        emit(
          PinFileNetworkCheckRunning(
            id: id,
            name: name,
            nameValidation: syncValidationResult.nameValidation,
            idValidation: syncValidationResult.idValidation,
          ),
        );
      } else if (state is PinFileFieldsValidationError) {
        final stateAsPinFileFieldsValidationError =
            state as PinFileFieldsValidationError;
        emit(
          PinFileFieldsValidationError(
            id: id,
            name: name,
            nameValidation: syncValidationResult.nameValidation,
            idValidation: syncValidationResult.idValidation,
            cancelled: stateAsPinFileFieldsValidationError.cancelled,
            networkError: stateAsPinFileFieldsValidationError.networkError,
            isArFsEntityValid:
                stateAsPinFileFieldsValidationError.isArFsEntityValid,
            isArFsEntityPublic:
                stateAsPinFileFieldsValidationError.isArFsEntityPublic,
            doesDataTransactionExist:
                stateAsPinFileFieldsValidationError.doesDataTransactionExist,
          ),
        );
      } else {
        logger.d('Unexpected state $state');
      }
    }
  }

  void _handlePinFileCancel(
    PinFileCancel event,
    Emitter<PinFileState> emit,
  ) {
    // TODO: tell the "file id resolver" to stop any ongoing requests
    emit(PinFileAbort(
      id: state.id,
      name: state.name,
      nameValidation: NameValidationResult.required,
      idValidation: IdValidationResult.required,
    ));
  }

  Future<void> _handlePinFileSubmit(
    PinFileSubmit event,
    Emitter<PinFileState> emit,
  ) async {
    final stateAsPinFileFieldsValid = state as PinFileFieldsValid;
    final profileState = _profileCubit.state as ProfileLoggedIn;
    final wallet = profileState.user.wallet;
    final signer = ArweaveSigner(wallet);

    emit(PinFileCreating(
      id: stateAsPinFileFieldsValid.id,
      name: stateAsPinFileFieldsValid.name,
      idValidation: stateAsPinFileFieldsValid.idValidation,
    ));

    final newFileEntity = FileEntity(
      size: stateAsPinFileFieldsValid.size,
      parentFolderId: _parentFolderId,
      name: stateAsPinFileFieldsValid.name,
      lastModifiedDate: DateTime.now(),
      id: const Uuid().v4(),
      driveId: _driveId,
      dataTxId: stateAsPinFileFieldsValid.dataTxId,
      dataContentType: stateAsPinFileFieldsValid.dataContentType,
      pinnedDataOwnerAddress: stateAsPinFileFieldsValid.pinnedDataOwnerAddress,
    );

    await _driveDao.transaction(() async {
      final driveKey = await _driveDao.getDriveKey(
        _driveId,
        profileState.user.cipherKey,
      );
      final fileKey = driveKey != null
          ? await _crypto.deriveFileKey(driveKey.key, newFileEntity.id!)
          : null;

      final isAPublicPin = fileKey == null;

      if (_turboUploadService.useTurboUpload) {
        final fileDataItem = await _arweave.prepareEntityDataItem(
          newFileEntity,
          wallet,
          key: fileKey,
          skipSignature: true,
        );

        if (isAPublicPin) {
          fileDataItem.addTag(
            EntityTag.arFsPin,
            'true',
          );
          fileDataItem.addTag(
            EntityTag.pinnedDataTx,
            newFileEntity.dataTxId!,
          );
        }

        await fileDataItem.sign(signer);

        await _turboUploadService.postDataItem(
          dataItem: fileDataItem,
          wallet: profileState.user.wallet,
        );
        newFileEntity.txId = fileDataItem.id;
      } else {
        final fileDataItem = await _arweave.prepareEntityTx(
          newFileEntity,
          wallet,
          fileKey,
          skipSignature: true,
        );

        if (isAPublicPin) {
          fileDataItem.addTag(
            EntityTag.arFsPin,
            'true',
          );
          fileDataItem.addTag(
            EntityTag.pinnedDataTx,
            newFileEntity.dataTxId!,
          );
        }

        await fileDataItem.sign(signer);

        await _arweave.postTx(fileDataItem);
        newFileEntity.txId = fileDataItem.id;
      }

      await _driveDao.writeFileEntity(newFileEntity);
      await _driveDao.insertFileRevision(newFileEntity.toRevisionCompanion(
        // FIXME: this is gonna change when we allow to ovewrite an existing file
        performedAction: RevisionAction.create,
      ));

      final drivePrivacy =
          driveKey != null ? DrivePrivacy.private : DrivePrivacy.public;
      PlausibleEventTracker.trackPinCreation(drivePrivacy: drivePrivacy);
    }).then((value) {
      emit(PinFileSuccess(
        id: state.id,
        name: state.name,
        nameValidation: state.nameValidation,
        idValidation: state.idValidation,
      ));
    }).catchError((err, stacktrace) {
      logger.e('PinFileSubmit error', err, stacktrace);
      emit(PinFileError(
        id: state.id,
        name: state.name,
        nameValidation: state.nameValidation,
        idValidation: state.idValidation,
      ));
    });
  }

  Future<SynchronousValidationResult> _runSynchronousValidation(
    String name,
    String id,
  ) async {
    final hasNameFieldChanged = state.name != name;
    final hasIdFieldChanged = state.id != id;

    NameValidationResult nameValidation =
        hasNameFieldChanged ? validateName(name) : state.nameValidation;
    final IdValidationResult idValidation =
        hasIdFieldChanged ? validateId(id) : state.idValidation;

    if (nameValidation == NameValidationResult.valid) {
      final doesItConflict = await _doesNameConflicts(name);
      if (doesItConflict) {
        nameValidation = NameValidationResult.conflicting;
      }
    }

    return SynchronousValidationResult(
      nameValidation: nameValidation,
      idValidation: idValidation,
    );
  }

// TODO: FIX
  Future<bool> _doesNameConflicts(String name) async {
    logger.d('About to check if entity with same name exists');
    final entityWithSameNameExists = await _driveDao.doesEntityWithNameExist(
      name: name,
      driveId: _driveId,
      parentFolderId: _parentFolderId,
    );

    logger.d('entityWithSameNameExists: $entityWithSameNameExists');

    return entityWithSameNameExists;
  }

  Future<ResolveIdResult> _runNetworkValidation(
    String id,
    String name,
    IdValidationResult idValidation,
  ) async {
    late final Future<ResolveIdResult> resolveFuture;
    if (idValidation == IdValidationResult.validTransactionId) {
      resolveFuture = _fileIdResolver.requestForTransactionId(id);
    } else {
      resolveFuture = _fileIdResolver.requestForFileId(id);
    }

    return resolveFuture;
  }

  NameValidationResult validateName(String value) {
    final nameRegex = RegExp(kFileNameRegex);
    final trimTrailingRegex = RegExp(kTrimTrailingRegex);

    if (value.isEmpty) {
      return NameValidationResult.required;
    } else if (!nameRegex.hasMatch(value) ||
        !trimTrailingRegex.hasMatch(value)) {
      return NameValidationResult.invalid;
    }

    return NameValidationResult.valid;
  }

  IdValidationResult validateId(String value) {
    // TODO: Replace this with isValidUuidFormat from `ardrive_utils`
    const kFileIdRegex =
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
    // TODO: Implement this method on `ardrive_utils`
    const kTransactionIdRegex = r'^[\w-+]{43}$';

    final fileIdRegex = RegExp(kFileIdRegex);
    final transactionIdRegex = RegExp(kTransactionIdRegex);

    final fileIdHasMatch = fileIdRegex.hasMatch(value);
    final transactionIdHasMatch = transactionIdRegex.hasMatch(value);

    if (value.isEmpty) {
      return IdValidationResult.required;
    } else if (fileIdHasMatch) {
      return IdValidationResult.validEntityId;
    } else if (transactionIdHasMatch) {
      return IdValidationResult.validTransactionId;
    } else {
      return IdValidationResult.invalid;
    }
  }

  @override
  Future<void> close() {
    nameTextController.dispose();
    return super.close();
  }
}

class SynchronousValidationResult {
  final NameValidationResult nameValidation;
  final IdValidationResult idValidation;

  const SynchronousValidationResult({
    required this.nameValidation,
    required this.idValidation,
  });

  bool get isNameValid => nameValidation == NameValidationResult.valid;
  bool get isIdValid =>
      idValidation == IdValidationResult.validEntityId ||
      idValidation == IdValidationResult.validTransactionId;

  bool get isValid => isNameValid && isIdValid;
}

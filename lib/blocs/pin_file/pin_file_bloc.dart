import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart';
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
  })  : _fileIdResolver = fileIdResolver,
        _arweave = arweave,
        _driveDao = driveDao,
        _turboUploadService = turboUploadService,
        _profileCubit = profileCubit,
        _driveId = driveID,
        _parentFolderId = parentFolderId,
        super(const PinFileInitial()) {
    nameTextController.text = '';

    on<FieldsChanged>((event, emit) async {
      String name = event.name;
      final String id = event.id;

      logger.d('FieldsChanged: name: $name, id: $id');

      if (name.isEmpty && id.isEmpty) {
        emit(const PinFileInitial());
        return;
      }

      final stateId = state.id;
      final hasIdChanged = stateId != id;

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

          syncValidationResult = await _runSynchronousValidation(name, id);

          emit(PinFileFieldsValid(
            id: id,
            name: name,
            nameValidation: syncValidationResult.nameValidation,
            isPrivate: fileInfo.isPrivate,
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
              isPrivate: stateAsPinFileFieldsValid.isPrivate,
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
    });

    on<PinFileCancel>((event, emit) {
      // TODO: tell the "file id resolver" to stop any ongoing requests
      emit(PinFileAbort(
        id: state.id,
        name: state.name,
        nameValidation: NameValidationResult.required,
        idValidation: IdValidationResult.required,
      ));
    });

    on<PinFileSubmit>((event, emit) async {
      final stateAsPinFileFieldsValid = state as PinFileFieldsValid;
      final profileState = _profileCubit.state as ProfileLoggedIn;

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
        pinnedDataOwnerAddress:
            stateAsPinFileFieldsValid.pinnedDataOwnerAddress,
      );

      await _driveDao.transaction(() async {
        final parentFolder = await _driveDao
            .folderById(driveId: _driveId, folderId: _parentFolderId)
            .getSingle();

        // TODO: re-enable
        /// It's disabled becaues the uploads are suceeding, but then it doesn't
        /// appear on chain
        const forceDisableTurbo = true;
        if (_turboUploadService.useTurboUpload && !forceDisableTurbo) {
          final fileDataItem = await _arweave.prepareEntityDataItem(
            newFileEntity,
            profileState.wallet,
            // TODO: key
          );

          await _turboUploadService.postDataItem(
            dataItem: fileDataItem,
            wallet: profileState.wallet,
          );
          newFileEntity.txId = fileDataItem.id;
        } else {
          final fileDataItem = await _arweave.prepareEntityTx(
            newFileEntity,
            profileState.wallet,
            null, // TODO: key
          );

          await _arweave.postTx(fileDataItem);
          newFileEntity.txId = fileDataItem.id;
        }

        final parentFolderPath = parentFolder.path;
        final filePath = '$parentFolderPath/${newFileEntity.name}';

        await _driveDao.writeFileEntity(newFileEntity, filePath);
        await _driveDao.insertFileRevision(newFileEntity.toRevisionCompanion(
          // FIXME: this is gonna change when we allow to ovewrite an existing file
          performedAction: RevisionAction.create,
        ));
      }).then((value) {
        emit(PinFileSuccess(
          id: state.id,
          name: state.name,
          nameValidation: state.nameValidation,
          idValidation: state.idValidation,
        ));
      }).catchError((err, stacktrace) {
        logger.d('PinFileSubmit error: $err - $stacktrace');
        emit(PinFileError(
          id: state.id,
          name: state.name,
          nameValidation: state.nameValidation,
          idValidation: state.idValidation,
        ));
      });
    });
  }

  Future<bool> doesNameConflicts(String name) async {
    try {
      logger.d(
        'About to check if entity with same name ($name) exists',
      );
      final entityWithSameNameExists = await _driveDao.doesEntityWithNameExist(
        name: name,
        driveId: _driveId,
        parentFolderId: _parentFolderId,
      );

      logger.d('entityWithSameNameExists: $entityWithSameNameExists');

      return entityWithSameNameExists;
    } catch (err) {
      // TODO: do somethin'
      rethrow;
    }
  }

  Future<SynchronousValidationResult> _runSynchronousValidation(
    String name,
    String id,
  ) async {
    NameValidationResult nameValidation = validateName(name);
    final IdValidationResult idValidation = validateId(id);

    if (nameValidation == NameValidationResult.valid) {
      final doesItConflict = await doesNameConflicts(name);
      if (doesItConflict) {
        nameValidation = NameValidationResult.conflicting;
      }
    }

    return SynchronousValidationResult(
      nameValidation: nameValidation,
      idValidation: idValidation,
    );
  }

  Future<FileInfo> _runNetworkValidation(
    String id,
    String name,
    IdValidationResult idValidation,
  ) async {
    late final Future<FileInfo> resolveFuture;
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
    const kFileIdRegex =
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
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
    // idTextController.dispose();
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

  @override
  String toString() {
    return 'SynchronousValidationResult { nameValidation: $nameValidation, '
        'idValidation: $idValidation, isValid: $isValid }';
  }
}

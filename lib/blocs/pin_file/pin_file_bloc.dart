import 'dart:async';

import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'file_id_resolver.dart';
part 'pin_file_event.dart';
part 'pin_file_state.dart';
part 'types.dart';

class PinFileBloc extends Bloc<PinFileEvent, PinFileState> {
  final FileIdResolver _fileIdResolver;
  // final idTextController = TextEditingController();
  final nameTextController = TextEditingController();

  PinFileBloc({
    required FileIdResolver fileIdResolver,
  })  : _fileIdResolver = fileIdResolver,
        super(const PinFileInitial()) {
    // idTextController.text = '';
    nameTextController.text = '';

    on<FieldsChanged>((event, emit) async {
      String name = event.name;
      final String id = event.id;

      if (name.isEmpty && id.isEmpty) {
        emit(const PinFileInitial());
        return;
      }

      final stateId = state.id;
      final hasIdChanged = stateId != id;

      SynchronousValidationResult syncValidationResult =
          _runSynchronousValidation(name, id);

      if (hasIdChanged && syncValidationResult.isIdValid) {
        emit(PinFileNetworkCheckRunning(
          id: id,
          name: name,
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
            nameTextController.text = newName;
            name = newName;
          }

          emit(PinFileFieldsValid(
            id: id,
            name: name,
            isPrivate: fileInfo.isPrivate,
            contentType: fileInfo.dataContentType,
            maybeLastUpdated: fileInfo.maybeLastUpdated,
            maybeLastModified: fileInfo.maybeLastModified,
            dateCreated: fileInfo.dateCreated,
            size: fileInfo.size,
            dataTxId: fileInfo.dataTxId,
          ));
        } catch (err) {
          if (err is FileIdResolverException) {
            final cancelled = err.cancelled;

            if (!cancelled) {
              emit(
                PinFileNetworkValidationError(
                  id: id,
                  name: name,
                  doesDataTransactionExist: err.doesDataTransactionExist,
                  isArFsEntityPublic: err.isArFsEntityPublic,
                  isArFsEntityValid: err.isArFsEntityValid,
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

      syncValidationResult = _runSynchronousValidation(name, id);

      if (!syncValidationResult.isValid) {
        emit(PinFileFieldsValidationError(
          id: id,
          name: name,
          nameValidation: syncValidationResult.nameValidation,
          idValidation: syncValidationResult.idValidation,
        ));
      } else {
        if (state is PinFileFieldsValid) {
          final stateAsPinFileFieldsValid = state as PinFileFieldsValid;
          emit(
            PinFileFieldsValid(
              id: id,
              name: name,
              isPrivate: stateAsPinFileFieldsValid.isPrivate,
              contentType: stateAsPinFileFieldsValid.contentType,
              dateCreated: stateAsPinFileFieldsValid.dateCreated,
              size: stateAsPinFileFieldsValid.size,
              dataTxId: stateAsPinFileFieldsValid.dataTxId,
              maybeLastUpdated: stateAsPinFileFieldsValid.maybeLastUpdated,
              maybeLastModified: stateAsPinFileFieldsValid.maybeLastModified,
            ),
          );
        } else if (state is PinFileNetworkCheckRunning) {
          emit(
            PinFileNetworkCheckRunning(
              id: id,
              name: name,
            ),
          );
        } else {
          // state is PinFileNetworkValidationError
          logger.d('State is $state');
        }
      }
    });

    on<PinFileCancel>((event, emit) {
      // TODO: tell the "file id resolver" to stop any ongoing requests
      emit(PinFileAbort(id: state.id, name: state.name));
    });

    on<PinFileSubmit>((event, emit) {
      throw UnimplementedError();
    });
  }

  SynchronousValidationResult _runSynchronousValidation(
    String name,
    String id,
  ) {
    final NameValidationResult nameValidation = validateName(name);
    final IdValidationResult idValidation = validateId(id);

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
      return IdValidationResult.validFileId;
    } else if (transactionIdHasMatch) {
      return IdValidationResult.validTransactionId;
    } else {
      return IdValidationResult.invalid;
    }
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
      idValidation == IdValidationResult.validFileId ||
      idValidation == IdValidationResult.validTransactionId;

  bool get isValid => isNameValid && isIdValid;

  @override
  String toString() {
    return 'SynchronousValidationResult { nameValidation: $nameValidation, '
        'idValidation: $idValidation, isValid: $isValid }';
  }
}

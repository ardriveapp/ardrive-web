import 'dart:async';

import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/debouncer.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'file_id_resolver.dart';
part 'pin_file_event.dart';
part 'pin_file_state.dart';
part 'types.dart';

class PinFileBloc extends Bloc<PinFileEvent, PinFileState> {
  final FileIdRessolver _fileIdRessolver;

  PinFileBloc({
    required FileIdRessolver fileIdRessolver,
  })  : _fileIdRessolver = fileIdRessolver,
        super(const PinFileInitial()) {
    on<FiledsChanged>((event, emit) async {
      final String name = event.name;
      final String id = event.id;

      if (name.isEmpty && id.isEmpty) {
        emit(const PinFileInitial());
        return;
      }

      final SynchronousValidationResult syncValidationResult =
          await _runSynchronousValidation(name, id);

      // FIXME: make none of the following methods to take `emit` as an argument
      if (!syncValidationResult.isValid) {
        emit(PinFileFieldsValidationError(
          id: id,
          name: name,
          nameValidation: syncValidationResult.nameValidation,
          idValidation: syncValidationResult.idValidation,
        ));
      } else {
        final stateId = state.id;
        final hasIdChanged = stateId != id;

        // run network check only if the id has changed
        if (hasIdChanged) {
          await _runNetworkValidation(
            emit,
            id,
            name,
            syncValidationResult.idValidation,
          );
        }
      }
    });
  }

  Future<SynchronousValidationResult> _runSynchronousValidation(
    String name,
    String id,
  ) {
    final NameValidationResult nameValidation = _validateName(name);
    final IdValidationResult idValidation = _validateId(id);

    return Future.value(SynchronousValidationResult(
      nameValidation: nameValidation,
      idValidation: idValidation,
    ));
  }

  Future<void> _runNetworkValidation(
    Emitter<PinFileState> emit,
    String id,
    String name,
    IdValidationResult idValidation,
  ) async {
    emit(PinFileNetworkCheckRunning(
      id: id,
      name: name,
    ));

    late final Future<FileInfo> ressolveFuture;
    if (idValidation == IdValidationResult.validTransactionId) {
      ressolveFuture = _fileIdRessolver.requestForTransactionId(id);
    } else {
      ressolveFuture = _fileIdRessolver.requestForFileId(id);
    }
    await _handleResolveIdFuture(ressolveFuture, emit, id, name);
  }

  Future<void> _handleResolveIdFuture(
    Future<FileInfo> ressolveFuture,
    Emitter<PinFileState> emit,
    String id,
    String name,
  ) {
    return ressolveFuture
        .then((fileDataFromNetwork) => emit(PinFileFieldsValid(
              id: id,
              // do not override the name if it's already set
              name: name.isEmpty ? (fileDataFromNetwork.maybeName ?? '') : name,
              isPrivate: fileDataFromNetwork.isPrivate,
              maybeName: fileDataFromNetwork.maybeName,
              contentType: fileDataFromNetwork.dataContentType,
              maybeLastUpdated: fileDataFromNetwork.maybeLastUpdated,
              maybeLastModified: fileDataFromNetwork.maybeLastModified,
              dateCreated: fileDataFromNetwork.dateCreated,
              size: fileDataFromNetwork.size,
              dataTxId: fileDataFromNetwork.dataTxId,
            )))
        .catchError((err) {
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
        throw err;
      }
    });
  }

  NameValidationResult _validateName(String value) {
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

  IdValidationResult _validateId(String value) {
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
}

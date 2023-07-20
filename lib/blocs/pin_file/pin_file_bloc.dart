import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'file_to_pin_ressolver.dart';
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

      final NameValidationResult nameValidation = _validateName(name);
      final IdValidationResult idValidation = _validateId(id);

      final isNameValid = nameValidation == NameValidationResult.valid;
      final isIdValid = idValidation == IdValidationResult.validFileId ||
          idValidation == IdValidationResult.validTransactionId;

      final bool isValid = isNameValid && isIdValid;
      if (!isValid) {
        emit(PinFileFieldsValidationError(
          id: id,
          name: name,
          nameValidation: nameValidation,
          idValidation: idValidation,
        ));
      } else {
        emit(PinFileNetworkCheckRunning(
          id: id,
          name: name,
        ));

        late final Future<FileData> resolveFuture;
        if (idValidation == IdValidationResult.validTransactionId) {
          resolveFuture = _fileIdRessolver.requestForTransactionId(id);
        } else {
          resolveFuture = _fileIdRessolver.requestForFileId(id);
        }

        await resolveFuture
            .then((fileDataFromNetwork) => emit(PinFileFieldsValid(
                  id: id,
                  name: name,
                  isPrivate: fileDataFromNetwork.isPrivate,
                  maybeName: fileDataFromNetwork.maybeName,
                  contentType: fileDataFromNetwork.contentType,
                  maybeLastUpdated: fileDataFromNetwork.maybeLastUpdated,
                  maybeLastModified: fileDataFromNetwork.maybeLastModified,
                  dateCreated: fileDataFromNetwork.dateCreated,
                  size: fileDataFromNetwork.size,
                  dataTxId: fileDataFromNetwork.dataTxId,
                )))
            .catchError(
          (err) {
            if (err is FileIdRessolverException) {
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
          },
        );
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

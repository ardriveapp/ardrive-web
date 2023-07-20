import 'package:ardrive/blocs/pin_file/file_to_pin_ressolver.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'pin_file_event.dart';
part 'pin_file_state.dart';

class PinFileBloc extends Bloc<PinFileEvent, PinFileState> {
  final FileIdRessolver _fileIdRessolver;

  PinFileBloc({
    required FileIdRessolver fileIdRessolver,
  })  : _fileIdRessolver = fileIdRessolver,
        super(const PinFileInitial()) {
    on<FiledsChanged>((event, emit) async {
      final String name = event.name;
      final String id = event.id;

      if (name.isEmpty || id.isEmpty) {
        emit(const PinFileInitial());
        return;
      }

      final NameValidationResult nameValidationMessage = _validateName(name);
      final bool isValid = nameValidationMessage == NameValidationResult.valid;
      // ignore: dead_code
      if (!isValid) {
        // TODO: do an actual validation
        // emit(const PinFileFieldsInvalid());
      } else {
        emit(PinFileNetworkCheckRunning(
          id: id,
          name: name,
        ));

        await _fileIdRessolver
            .resolve(id)
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
}

enum NameValidationResult {
  required,
  invalid,
  valid,
}

part of 'pin_file_bloc.dart';

abstract class PinFileState extends Equatable {
  final String id;
  final String name;
  final IdValidationResult idValidation;
  final NameValidationResult nameValidation;

  const PinFileState({
    required this.id,
    required this.name,
    required this.idValidation,
    required this.nameValidation,
  });
}

class PinFileInitial extends PinFileState {
  const PinFileInitial()
      : super(
          id: '',
          name: '',
          idValidation: IdValidationResult.required,
          nameValidation: NameValidationResult.required,
        );

  @override
  List<Object> get props => [];
}

class PinFileFieldsValidationError extends PinFileState {
  // network check
  final bool cancelled;
  final bool networkError;
  final bool isArFsEntityValid;
  final bool isArFsEntityPublic;
  final bool doesDataTransactionExist;

  const PinFileFieldsValidationError({
    required super.id,
    required super.name,
    required super.nameValidation,
    required super.idValidation,
    required this.cancelled,
    required this.networkError,
    required this.isArFsEntityValid,
    required this.isArFsEntityPublic,
    required this.doesDataTransactionExist,
  });

  @override
  List<Object> get props => [
        id,
        name,
        nameValidation,
        idValidation,
      ];
}

class PinFileNetworkCheckRunning extends PinFileState {
  const PinFileNetworkCheckRunning({
    required super.id,
    required super.name,
    required super.nameValidation,
    required super.idValidation,
  });

  @override
  List<Object> get props => [id, name, nameValidation, idValidation];
}

// class PinFileNetworkValidationError extends PinFileState {
//   final bool doesDataTransactionExist;
//   final bool isArFsEntityValid;
//   final bool isArFsEntityPublic;

//   const PinFileNetworkValidationError({
//     required super.id,
//     required super.name,
//     required this.isArFsEntityValid,
//     required this.isArFsEntityPublic,
//     required this.doesDataTransactionExist,
//   });

//   @override
//   List<Object?> get props => [
//         id,
//         name,
//         isArFsEntityValid,
//         isArFsEntityPublic,
//         doesDataTransactionExist,
//       ];
// }

class PinFileFieldsValid extends PinFileState {
  final bool isPrivate; // TODO: use an enum
  final String contentType; // TODO: use an enum
  final DateTime? maybeLastUpdated;
  final DateTime? maybeLastModified;
  final DateTime dateCreated;
  final int size;
  final String dataTxId;

  const PinFileFieldsValid({
    required String id,
    required String name,
    required NameValidationResult nameValidation,
    required this.isPrivate,
    required this.contentType,
    this.maybeLastUpdated,
    this.maybeLastModified,
    required this.dateCreated,
    required this.size,
    required this.dataTxId,
  }) : super(
          id: id,
          name: name,
          nameValidation: nameValidation,
          idValidation: IdValidationResult.validEntityId,
        );

  @override
  List<Object?> get props => [
        id,
        name,
        isPrivate,
        contentType,
        maybeLastUpdated,
        maybeLastModified,
        dateCreated,
        size,
        dataTxId,
      ];
}

class PinFileCreating extends PinFileState {
  const PinFileCreating({
    required super.id,
    required super.name,
    required super.nameValidation,
    required super.idValidation,
  });

  @override
  List<Object> get props => [];
}

class PinFileAbort extends PinFileState {
  const PinFileAbort({
    required super.id,
    required super.name,
    required super.nameValidation,
    required super.idValidation,
  });

  @override
  List<Object> get props => [];
}

class PinFileSucess extends PinFileState {
  const PinFileSucess({
    required super.id,
    required super.name,
    required super.nameValidation,
    required super.idValidation,
  });

  @override
  List<Object> get props => [];
}

class PinFileError extends PinFileState {
  const PinFileError({
    required super.id,
    required super.name,
    required super.nameValidation,
    required super.idValidation,
  });

  @override
  List<Object> get props => [];
}

part of 'pin_file_bloc.dart';

abstract class PinFileState extends Equatable {
  final String id;
  final String name;

  const PinFileState({
    required this.id,
    required this.name,
  });
}

class PinFileInitial extends PinFileState {
  const PinFileInitial() : super(id: '', name: '');

  @override
  List<Object> get props => [];
}

class PinFileFieldsValidationError extends PinFileState {
  final NameValidationResult nameValidation;
  final IdValidationResult idValidation;

  const PinFileFieldsValidationError({
    required super.id,
    required super.name,
    required this.nameValidation,
    required this.idValidation,
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
  });

  @override
  List<Object> get props => [id, name];
}

class PinFileNetworkValidationError extends PinFileState {
  final bool doesDataTransactionExist;
  final bool isArFsEntityValid;
  final bool isArFsEntityPublic;

  const PinFileNetworkValidationError({
    required super.id,
    required super.name,
    required this.isArFsEntityValid,
    required this.isArFsEntityPublic,
    required this.doesDataTransactionExist,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        isArFsEntityValid,
        isArFsEntityPublic,
        doesDataTransactionExist,
      ];
}

class PinFileFieldsValid extends PinFileState {
  final bool isPrivate; // TODO: use an enum
  final String contentType; // TODO: use an enum
  final DateTime? maybeLastUpdated;
  final DateTime? maybeLastModified;
  final DateTime dateCreated;
  final int size;
  final String dataTxId;

  const PinFileFieldsValid({
    required super.id,
    required super.name,
    required this.isPrivate,
    required this.contentType,
    this.maybeLastUpdated,
    this.maybeLastModified,
    required this.dateCreated,
    required this.size,
    required this.dataTxId,
  });

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
  const PinFileCreating({required super.id, required super.name});

  @override
  List<Object> get props => [];
}

class PinFileAbort extends PinFileState {
  const PinFileAbort({required super.id, required super.name});

  @override
  List<Object> get props => [];
}

class PinFileSucess extends PinFileState {
  const PinFileSucess({required super.id, required super.name});

  @override
  List<Object> get props => [];
}

class PinFileError extends PinFileState {
  const PinFileError({required super.id, required super.name});

  @override
  List<Object> get props => [];
}

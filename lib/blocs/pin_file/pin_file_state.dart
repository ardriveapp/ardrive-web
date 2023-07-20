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
  final bool isNameValid;
  final bool isIdValid;

  const PinFileFieldsValidationError({
    required super.id,
    required super.name,
    required this.isNameValid,
    required this.isIdValid,
  });

  @override
  List<Object> get props => [
        id,
        name,
        isNameValid,
        isIdValid,
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
  final String? maybeName;
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
    this.maybeName,
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
        maybeName,
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

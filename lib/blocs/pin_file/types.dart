part of 'pin_file_bloc.dart';

enum NameValidationResult {
  required,
  invalid,
  valid,
}

enum IdValidationResult {
  required,
  invalid,
  validFileId,
  validTransactionId,
}

class FileData {
  final bool isPrivate; // TODO: use an enum
  final String? maybeName;
  final String contentType; // TODO: use an enum
  final DateTime? maybeLastUpdated;
  final DateTime? maybeLastModified;
  final DateTime dateCreated;
  final int size;
  final String dataTxId;

  const FileData({
    required this.isPrivate,
    this.maybeName,
    required this.contentType,
    this.maybeLastUpdated,
    this.maybeLastModified,
    required this.dateCreated,
    required this.size,
    required this.dataTxId,
  });
}

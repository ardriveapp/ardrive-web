part of 'pin_file_bloc.dart';

enum NameValidationResult {
  required,
  invalid,
  conflicting,
  valid,
}

enum IdValidationResult {
  required,
  invalid,
  validEntityId,
  validTransactionId,
}

class FileInfo {
  final DrivePrivacy privacy;
  final String? maybeName;
  final String dataContentType; // TODO: use an enum
  final DateTime? maybeLastUpdated;
  final DateTime? maybeLastModified;
  final DateTime dateCreated;
  final int size;
  final String dataTxId;
  final String pinnedDataOwnerAddress;

  const FileInfo({
    required this.privacy,
    this.maybeName,
    required this.dataContentType,
    this.maybeLastUpdated,
    this.maybeLastModified,
    required this.dateCreated,
    required this.size,
    required this.dataTxId,
    required this.pinnedDataOwnerAddress,
  });
}

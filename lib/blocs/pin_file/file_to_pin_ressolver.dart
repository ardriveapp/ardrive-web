part of 'pin_file_bloc.dart';

class NetworkFileIdRessolver implements FileIdRessolver {
  @override
  Future<FileData> requestForFileId(String id) {
    // TODO: implement requestForFileId
    throw UnimplementedError();
  }

  @override
  Future<FileData> requestForTransactionId(String id) {
    // TODO: implement requestForTransactionId
    throw UnimplementedError();
  }
}

abstract class FileIdRessolver {
  Future<FileData> requestForTransactionId(String id);
  Future<FileData> requestForFileId(String id);
}

class FileIdRessolverException implements Exception {
  final String id;
  final bool cancelled;
  final bool networkError;
  final bool isArFsEntityValid;
  final bool isArFsEntityPublic;
  final bool doesDataTransactionExist;

  const FileIdRessolverException({
    required this.id,
    required this.cancelled,
    required this.networkError,
    required this.isArFsEntityValid,
    required this.isArFsEntityPublic,
    required this.doesDataTransactionExist,
  });
}

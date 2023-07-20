class FileIdRessolver {
  Future<FileData> resolve(String id) async {
    if (id == 'unexisting') {
      throw FileIdRessolverException(
        id: id,
        networkError: false,
        doesDataTransactionExist: false,
        isArFsEntityValid: false,
        isArFsEntityPublic: false,
      );
    } else if (id == 'invalid') {
      throw FileIdRessolverException(
        id: id,
        networkError: false,
        isArFsEntityValid: false,
        doesDataTransactionExist: true,
        isArFsEntityPublic: false,
      );
    } else if (id == 'private') {
      throw FileIdRessolverException(
        id: id,
        networkError: false,
        isArFsEntityValid: true,
        isArFsEntityPublic: false,
        doesDataTransactionExist: true,
      );
    } else if (id == 'networkError') {
      throw FileIdRessolverException(
        id: id,
        networkError: true,
        isArFsEntityValid: false,
        isArFsEntityPublic: false,
        doesDataTransactionExist: false,
      );
    }

    final mockData = FileData(
      isPrivate: false,
      contentType: 'application/json',
      dateCreated: DateTime.now(),
      size: 1024,
      dataTxId: 'dataTxId',

      ///
      maybeName: 'alpargata',
      maybeLastModified: DateTime.now(),
      maybeLastUpdated: DateTime.now(),
    );

    return mockData;
  }
}

abstract class FileRequester {
  Future<FileData> requestForTransactionId(String id);
  Future<FileData> requestForFileId(String id);
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

class FileIdRessolverException implements Exception {
  final String id;
  final bool networkError;
  final bool isArFsEntityValid;
  final bool isArFsEntityPublic;
  final bool doesDataTransactionExist;

  const FileIdRessolverException({
    required this.id,
    required this.networkError,
    required this.isArFsEntityValid,
    required this.isArFsEntityPublic,
    required this.doesDataTransactionExist,
  });
}

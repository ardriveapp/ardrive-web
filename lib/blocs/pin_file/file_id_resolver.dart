part of 'pin_file_bloc.dart';

class NetworkFileIdResolver implements FileIdResolver {
  // TODO: add a debouncer and a completer

  final ArweaveService arweave;

  const NetworkFileIdResolver({
    required this.arweave,
  });

  @override
  Future<FileInfo> requestForFileId(String id) async {
    late FileEntity? fileEntity;
    try {
      fileEntity = await arweave.getLatestFileEntityWithId(id);
    } catch (_) {
      throw FileIdResolverException(
        id: id,
        cancelled: false,
        networkError: true,
        isArFsEntityValid: false,
        isArFsEntityPublic: false,
        doesDataTransactionExist: false,
      );
    }

    if (fileEntity == null) {
      // It either doesn't exist, is invalid, or private.

      throw FileIdResolverException(
        id: id,
        cancelled: false,
        networkError: false,
        isArFsEntityValid: false,
        isArFsEntityPublic: false,
        doesDataTransactionExist: false,
      );
    }

    final FileInfo fileInfo = FileInfo(
      isPrivate: false,
      maybeName: fileEntity.name,
      dataContentType: fileEntity.dataContentType!,
      maybeLastUpdated: fileEntity.lastModifiedDate,
      maybeLastModified: fileEntity.lastModifiedDate,
      dateCreated: fileEntity.lastModifiedDate!,
      size: fileEntity.size!,
      dataTxId: fileEntity.dataTxId!,
      pinnedDataOwnerAddress: fileEntity.ownerAddress,
    );

    return fileInfo;
  }

  @override
  Future<FileInfo> requestForTransactionId(String id) {
    // TODO: implement requestForTransactionId
    throw UnimplementedError();
  }
}

abstract class FileIdResolver {
  Future<FileInfo> requestForTransactionId(String id);
  Future<FileInfo> requestForFileId(String id);
}

class FileIdResolverException implements Exception {
  final String id;
  final bool cancelled;
  final bool networkError;
  final bool isArFsEntityValid;
  final bool isArFsEntityPublic;
  final bool doesDataTransactionExist;

  const FileIdResolverException({
    required this.id,
    required this.cancelled,
    required this.networkError,
    required this.isArFsEntityValid,
    required this.isArFsEntityPublic,
    required this.doesDataTransactionExist,
  });
}

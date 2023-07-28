part of 'pin_file_bloc.dart';

class NetworkFileIdResolver implements FileIdResolver {
  // TODO: add a debouncer and a completer

  final ArweaveService arweave;
  final ConfigService configService;
  final Client httpClient;

  const NetworkFileIdResolver({
    required this.arweave,
    required this.httpClient,
    required this.configService,
  });

  @override
  Future<FileInfo> requestForFileId(FileID fileId) async {
    late FileEntity? fileEntity;
    try {
      fileEntity = await arweave.getLatestFileEntityWithId(fileId);
    } catch (_) {
      throw FileIdResolverException(
        id: fileId,
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
        id: fileId,
        cancelled: false,
        networkError: false,
        isArFsEntityValid: false,
        isArFsEntityPublic: false,
        doesDataTransactionExist: false,
      );
    }

    final FileInfo fileInfo = FileInfo(
      privacy: DrivePrivacy.public,
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
  Future<FileInfo> requestForTransactionId(TxID dataTxId) async {
    final uri = Uri.parse(
      '${configService.config.defaultArweaveGatewayUrl}/$dataTxId',
    );
    final response = await httpClient.head(uri);

    final Map headers = response.headers;
    final String? contentTypeHeader = headers['content-type'];
    final int? sizeHeader = int.tryParse(headers['content-length'] ?? '');

    if (response.statusCode != 200 ||
        sizeHeader == null ||
        contentTypeHeader == null) {
      throw FileIdResolverException(
        id: dataTxId,
        cancelled: false,
        networkError: false,
        isArFsEntityValid: false,
        isArFsEntityPublic: false,
        doesDataTransactionExist: false,
      );
    }

    final transactionDetails = await arweave.getTransactionDetails(dataTxId);

    if (transactionDetails == null) {
      throw FileIdResolverException(
        id: dataTxId,
        cancelled: false,
        networkError: false,
        isArFsEntityValid: false,
        isArFsEntityPublic: false,
        doesDataTransactionExist: false,
      );
    }

    final tags = transactionDetails.tags;
    final cipherIvTag = tags.firstWhereOrNull(
      (tag) => tag.name == 'Cipher-Iv' && tag.value.isNotEmpty,
    );

    final FileInfo fileInfo = FileInfo(
      privacy: cipherIvTag == null ? DrivePrivacy.public : DrivePrivacy.private,
      maybeName: null,
      dataContentType: contentTypeHeader,
      maybeLastUpdated: null,
      maybeLastModified: null,
      dateCreated: DateTime.now(),
      size: sizeHeader,
      dataTxId: dataTxId,
      pinnedDataOwnerAddress: transactionDetails.owner.address,
    );

    return fileInfo;
  }
}

abstract class FileIdResolver {
  Future<FileInfo> requestForTransactionId(TxID id);
  Future<FileInfo> requestForFileId(FileID id);
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

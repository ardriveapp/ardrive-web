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
  Future<ResolveIdResult> requestForFileId(FileID fileId) async {
    FileEntity? fileEntity;
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
      logger.d(
          'Failed to get file entity. It either doesnt exist, is invalid, or private');

      throw FileIdResolverException(
        id: fileId,
        cancelled: false,
        networkError: false,
        isArFsEntityValid: false,
        isArFsEntityPublic: false,
        doesDataTransactionExist: false,
      );
    }

    final _OwnerPrivacySizeAndType ownerAndPrivacyOfData =
        await _getOwnerAndPrivacyOfDataTransaction(fileEntity.dataTxId!);

    final ResolveIdResult fileInfo = ResolveIdResult(
      privacy: ownerAndPrivacyOfData.privacy,
      maybeName: fileEntity.name,
      dataContentType: fileEntity.dataContentType!,
      maybeLastUpdated: fileEntity.lastModifiedDate,
      maybeLastModified: fileEntity.lastModifiedDate,
      dateCreated: fileEntity.lastModifiedDate!,
      size: fileEntity.size!,
      dataTxId: fileEntity.dataTxId!,
      pinnedDataOwnerAddress: ownerAndPrivacyOfData.ownerAddress,
    );

    return fileInfo;
  }

  @override
  Future<ResolveIdResult> requestForTransactionId(TxID dataTxId) async {
    final _OwnerPrivacySizeAndType metadataTxInfo =
        await _getOwnerAndPrivacyOfDataTransaction(dataTxId);

    String type;

    if (metadataTxInfo.type == null) {
      final uri = Uri.parse(
        '${configService.config.defaultArweaveGatewayForDataRequest.url}/$dataTxId',
      );
      final response = await retry(
        () => httpClient.head(uri),
        maxAttempts: 3,
      );

      final Map headers = response.headers;
      final String? contentTypeHeader = headers['content-type'];

      if (response.statusCode != 200) {
        throw FileIdResolverException(
          id: dataTxId,
          cancelled: false,
          networkError: true,
          isArFsEntityValid: false,
          isArFsEntityPublic: false,
          doesDataTransactionExist: false,
        );
      } else if (contentTypeHeader == null) {
        throw FileIdResolverException(
          id: dataTxId,
          cancelled: false,
          networkError: false,
          isArFsEntityValid: false,
          isArFsEntityPublic: false,
          doesDataTransactionExist: true,
        );
      }

      // Mime without extra properties such as charset.
      type = contentTypeHeader.replaceFirst(RegExp(r';.*$'), '');
    } else {
      type = metadataTxInfo.type!;
    }

    final ResolveIdResult fileInfo = ResolveIdResult(
      privacy: metadataTxInfo.privacy,
      maybeName: null,
      dataContentType: type,
      maybeLastUpdated: null,
      maybeLastModified: null,
      dateCreated: DateTime.now(),
      size: metadataTxInfo.size,
      dataTxId: dataTxId,
      pinnedDataOwnerAddress: metadataTxInfo.ownerAddress,
    );

    return fileInfo;
  }

  Future<_OwnerPrivacySizeAndType> _getOwnerAndPrivacyOfDataTransaction(
    TxID dataTxId,
  ) async {
    final transactionDetails = await arweave.getInfoOfTxToBePinned(dataTxId);

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

    final size = int.tryParse(transactionDetails.data.size);
    final type = transactionDetails.data.type;

    if (size == null) {
      throw FileIdResolverException(
        id: dataTxId,
        cancelled: false,
        networkError: false,
        isArFsEntityValid: false,
        isArFsEntityPublic: false,
        doesDataTransactionExist: true,
      );
    }

    final tags = transactionDetails.tags;
    final cipherIvTag = tags.firstWhereOrNull(
      (tag) => tag.name == 'Cipher-Iv' && tag.value.isNotEmpty,
    );

    return _OwnerPrivacySizeAndType(
      ownerAddress: transactionDetails.owner.address,
      privacy: cipherIvTag == null ? DrivePrivacy.public : DrivePrivacy.private,
      size: size,
      type: type,
    );
  }
}

abstract class FileIdResolver {
  Future<ResolveIdResult> requestForTransactionId(TxID id);
  Future<ResolveIdResult> requestForFileId(FileID id);
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

class _OwnerPrivacySizeAndType {
  final String ownerAddress;
  final DrivePrivacy privacy;
  final int size;
  final String? type;

  const _OwnerPrivacySizeAndType({
    required this.ownerAddress,
    required this.privacy,
    required this.size,
    required this.type,
  });
}

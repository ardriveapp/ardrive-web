import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';

/// Exception thrown when folder metadata upload fails.
class FolderMetadataUploadException implements Exception {
  final String message;
  final dynamic originalError;

  FolderMetadataUploadException(
    this.message, {
    this.originalError,
  });

  @override
  String toString() =>
      'FolderMetadataUploadException: $message${originalError != null ? '\nOriginal error: $originalError' : ''}';
}

/// Result of a folder metadata upload operation.
class FolderMetadataUploadResult {
  final String metadataTxId;
  final List<Tag> tags;

  FolderMetadataUploadResult({
    required this.metadataTxId,
    required this.tags,
  });
}

/// Use case for uploading folder metadata to Arweave.
class UploadFolderMetadata {
  final ArweaveService _arweaveService;
  final TurboUploadService _turboUploadService;

  UploadFolderMetadata({
    required ArweaveService arweaveService,
    required TurboUploadService turboUploadService,
  })  : _arweaveService = arweaveService,
        _turboUploadService = turboUploadService;

  /// Uploads folder metadata to Arweave.
  ///
  /// Takes a [FolderEntity] object containing the folder's metadata and a list of [Tag]s
  /// to be attached to the metadata transaction.
  ///
  /// Returns a [FolderMetadataUploadResult] containing the metadata transaction ID
  /// and the tags that were attached to it.
  ///
  /// Throws [FolderMetadataUploadException] if the upload fails.
  Future<FolderMetadataUploadResult> call({
    required FolderEntity folderEntity,
    required List<Tag> customTags,
    required bool isPrivate,
    required Wallet wallet,
    SecretKey? driveKey,
  }) async {
    try {
      final signer = ArweaveSigner(wallet);

      // Prepare the metadata data item
      final metadataDataItem = await _arweaveService.prepareEntityDataItem(
        folderEntity,
        wallet,
        key: driveKey,
      );

      // Add the provided tags
      for (final tag in customTags) {
        metadataDataItem.addTag(tag.name, tag.value);
      }

      // Sign the data item
      await metadataDataItem.sign(signer);

      // Upload using either Turbo or Arweave service
      if (_turboUploadService.useTurboUpload) {
        await _turboUploadService.postDataItem(
          dataItem: metadataDataItem,
          wallet: wallet,
        );
      } else {
        // Convert DataItem to Transaction for Arweave upload
        final binary = await metadataDataItem.asBinary();
        final tx = Transaction.withBlobData(data: binary.toBytes());

        // Copy tags from DataItem to Transaction
        for (final tag in metadataDataItem.tags) {
          tx.addTag(tag.name, tag.value);
        }

        // Prepare and sign the transaction
        final preparedTx = await _arweaveService.client.transactions.prepare(
          tx,
          wallet,
        );
        await preparedTx.sign(signer);

        await _arweaveService.postTx(preparedTx);
      }

      return FolderMetadataUploadResult(
        metadataTxId: metadataDataItem.id,
        tags: metadataDataItem.tags,
      );
    } catch (e) {
      logger.e('Failed to upload folder metadata', e);
      throw FolderMetadataUploadException(
        'Failed to upload folder metadata',
        originalError: e,
      );
    }
  }
}

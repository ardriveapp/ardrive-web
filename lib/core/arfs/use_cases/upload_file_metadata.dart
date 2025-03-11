import 'package:ardrive/core/arfs/repository/file_metadata_repository.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';

/// Exception thrown when file metadata upload fails.
class FileMetadataUploadException implements Exception {
  final String message;
  final dynamic originalError;

  FileMetadataUploadException(
    this.message, {
    this.originalError,
  });

  @override
  String toString() =>
      'FileMetadataUploadException: $message${originalError != null ? '\nOriginal error: $originalError' : ''}';
}

/// Result of a file metadata upload operation.
class FileMetadataUploadResult {
  final String metadataTxId;
  final List<Tag> tags;

  FileMetadataUploadResult({
    required this.metadataTxId,
    required this.tags,
  });
}

/// Use case for uploading file metadata to Arweave.
class UploadFileMetadata {
  final ArweaveService _arweaveService;
  final TurboUploadService _turboUploadService;

  UploadFileMetadata({
    required ArweaveService arweaveService,
    required TurboUploadService turboUploadService,
  })  : _arweaveService = arweaveService,
        _turboUploadService = turboUploadService;

  /// Uploads file metadata to Arweave.
  ///
  /// Takes a [FileMetadata] object containing the file's metadata and a list of [Tag]s
  /// to be attached to the metadata transaction.
  ///
  /// Returns a [FileMetadataUploadResult] containing the metadata transaction ID
  /// and the tags that were attached to it.
  ///
  /// Throws [FileMetadataUploadException] if the upload fails.
  Future<FileMetadataUploadResult> call({
    required FileEntity fileEntity,
    required List<Tag> customTags,
    required bool isPrivate,
    required Wallet wallet,
  }) async {
    try {
      final signer = ArweaveSigner(wallet);

      // Prepare the metadata data item
      final metadataDataItem = await _arweaveService.prepareEntityDataItem(
        fileEntity,
        wallet,
        skipSignature: true,
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

      return FileMetadataUploadResult(
        metadataTxId: metadataDataItem.id,
        tags: metadataDataItem.tags,
      );
    } catch (e) {
      logger.e('Failed to upload file metadata', e);
      throw FileMetadataUploadException(
        'Failed to upload file metadata',
        originalError: e,
      );
    }
  }
}

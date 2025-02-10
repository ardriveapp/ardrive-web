import 'dart:convert';

import 'package:ardrive/core/arfs/repository/file_metadata_repository.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';

class FileMetadataRepositoryImpl implements FileMetadataRepository {
  final ArweaveService _arweaveService;

  FileMetadataRepositoryImpl(this._arweaveService);

  @override
  Future<FileMetadataResult> getFileMetadata(List<String> fileIds) async {
    logger.i('Fetching metadata for ${fileIds.length} files');

    final metadata = <String, FileMetadata>{};
    final failures = <FileMetadataFailure>[];

    for (final txId in fileIds) {
      try {
        logger.d('Fetching metadata for transaction: $txId');

        final tx = await _arweaveService.getTransactionDetails(txId);
        if (tx == null) {
          logger.w('Transaction not found for ID: $txId');
          failures.add(FileMetadataFailure(
            fileId: txId,
            error: 'Transaction not found',
          ));
          continue;
        }

        final response = await _arweaveService.client.api.getSandboxedTx(txId);
        final metadataJson = response.bodyBytes;
        if (metadataJson.isEmpty) {
          logger.w('Empty metadata for transaction: $txId');
          failures.add(FileMetadataFailure(
            fileId: txId,
            error: 'Empty metadata',
          ));
          continue;
        }

        final metadataData = json.decode(utf8.decode(metadataJson));
        final metadataTags = Map<String, String>.fromEntries(
          tx.tags.map((tag) => MapEntry(tag.name, tag.value)),
        );

        // Extract required fields
        final name = metadataData['name'] as String;
        final size = metadataData['size'] as int;
        final lastModifiedDate = DateTime.fromMillisecondsSinceEpoch(
          metadataData['lastModifiedDate'] as int,
        );
        final dataTxId = metadataData['dataTxId'] as String;
        final contentType =
            metadataTags['Content-Type'] ?? 'application/octet-stream';

        metadata[txId] = FileMetadata(
          id: txId,
          name: name,
          dataTxId: dataTxId,
          contentType: contentType,
          size: size,
          lastModifiedDate: lastModifiedDate,
          customMetadata: _extractCustomMetadata(metadataTags),
        );

        logger.d('Successfully fetched metadata for transaction: $txId');
      } catch (e) {
        logger.e('Failed to fetch metadata for transaction: $txId', e);
        failures.add(FileMetadataFailure(
          fileId: txId,
          error: e.toString(),
        ));
      }
    }

    return FileMetadataResult(
      metadata: metadata,
      failures: failures,
    );
  }

  Map<String, String> _extractCustomMetadata(Map<String, String> tags) {
    return Map.fromEntries(
      tags.entries.where((entry) => entry.key.startsWith('User-')),
    );
  }
}

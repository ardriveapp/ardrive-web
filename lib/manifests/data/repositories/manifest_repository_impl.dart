import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/manifests/domain/entities/manifest.dart';
import 'package:ardrive/manifests/domain/models/manifest_result.dart';
import 'package:ardrive/manifests/domain/repositories/manifest_repository.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';

class ManifestRepositoryImpl implements ManifestRepository {
  final ArweaveService _arweaveService;
  final DownloadService _downloader;

  ManifestRepositoryImpl(this._arweaveService, this._downloader);

  @override
  Future<ManifestResult> getManifest(String transactionId) async {
    try {
      logger.i('Fetching manifest for transaction: $transactionId');

      // Get transaction details from Arweave
      final tx = await _arweaveService.getInfoOfTxToBePinned(transactionId);
      if (tx == null) {
        logger.e('Transaction not found: $transactionId');
        return const ManifestResult.failure(
          NotFoundFailure('Manifest transaction not found'),
        );
      }

      // Download manifest data
      final Uint8List manifestData = await _downloader.download(
        transactionId,
        true, // isManifest = true
      );

      logger.d(
          'Successfully downloaded manifest data (${manifestData.length} bytes)');

      try {
        // Parse manifest JSON
        final Map<String, dynamic> manifestJson = json.decode(
          utf8.decode(manifestData),
        );

        // Create Manifest instance
        final manifest = Manifest.fromJson(manifestJson);
        return ManifestResult.success(manifest);
      } catch (e) {
        logger.e('Failed to parse manifest data', e);
        return ManifestResult.failure(
          InvalidManifestFailure('Failed to parse manifest data: $e'),
        );
      }
    } catch (e) {
      logger.e('Failed to fetch manifest', e);
      return ManifestResult.failure(
        NetworkFailure('Failed to fetch manifest: $e'),
      );
    }
  }
}

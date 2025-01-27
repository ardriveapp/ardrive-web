import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/utils/logger.dart';

class ManifestDataSource {
  final DownloadService _downloadService;

  ManifestDataSource(this._downloadService);

  /// Downloads and parses manifest data from Arweave.
  ///
  /// [manifestTxId] is the transaction ID of the manifest.
  /// Returns a [Future] that completes with a [Map] containing the manifest data.
  /// Throws a [ManifestDownloadException] if the download fails.
  /// Throws a [ManifestParseException] if the manifest data is invalid.
  Future<Map<String, dynamic>> downloadAndParseManifest(
      String manifestTxId) async {
    try {
      logger.i('Downloading manifest data for transaction: $manifestTxId');

      // Download the manifest data
      final Uint8List manifestData = await _downloadService.download(
        manifestTxId,
        true, // isManifest = true
      );

      logger.d(
          'Successfully downloaded manifest data (${manifestData.length} bytes)');

      // Parse the manifest JSON
      try {
        final Map<String, dynamic> manifestJson = json.decode(
          utf8.decode(manifestData),
        );

        // Validate manifest structure
        if (!_isValidManifest(manifestJson)) {
          throw ManifestParseException('Invalid manifest structure');
        }

        logger.d('Successfully parsed manifest data');
        return manifestJson;
      } catch (e) {
        logger.e('Failed to parse manifest data', e);
        throw ManifestParseException('Failed to parse manifest data: $e');
      }
    } catch (e) {
      logger.e('Failed to download manifest data', e);
      throw ManifestDownloadException('Failed to download manifest data: $e');
    }
  }

  /// Extracts file IDs from the manifest data.
  ///
  /// [manifestJson] is the parsed manifest data.
  /// Returns a [List] of file IDs.
  List<String> extractFileIds(Map<String, dynamic> manifestJson) {
    final Set<String> fileIds = {};

    try {
      // Extract file IDs from paths
      final paths = manifestJson['paths'] as Map<String, dynamic>;
      for (final pathData in paths.values) {
        if (pathData is Map<String, dynamic> && pathData.containsKey('id')) {
          fileIds.add(pathData['id'] as String);
        }
      }

      // Extract file ID from index if present
      final index = manifestJson['index'];
      if (index is Map<String, dynamic> && index.containsKey('id')) {
        fileIds.add(index['id'] as String);
      }

      // Extract file ID from fallback if present
      final fallback = manifestJson['fallback'];
      if (fallback is Map<String, dynamic> && fallback.containsKey('id')) {
        fileIds.add(fallback['id'] as String);
      }

      logger.d('Extracted ${fileIds.length} unique file IDs from manifest');
      return fileIds.toList();
    } catch (e) {
      logger.e('Failed to extract file IDs from manifest', e);
      throw ManifestParseException('Failed to extract file IDs: $e');
    }
  }

  /// Validates the basic structure of a manifest.
  bool _isValidManifest(Map<String, dynamic> manifestJson) {
    return manifestJson.containsKey('manifest') &&
        manifestJson.containsKey('version') &&
        manifestJson.containsKey('paths') &&
        manifestJson['paths'] is Map;
  }
}

class ManifestDownloadException implements Exception {
  final String message;
  ManifestDownloadException(this.message);
  @override
  String toString() => 'ManifestDownloadException: $message';
}

class ManifestParseException implements Exception {
  final String message;
  ManifestParseException(this.message);
  @override
  String toString() => 'ManifestParseException: $message';
}

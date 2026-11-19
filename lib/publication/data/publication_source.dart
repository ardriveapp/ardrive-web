import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/publication/data/snapshot_download.dart';
import 'package:http/http.dart' as http;

/// Reads a publication's own files from the page's manifest, relative to the
/// page (docs/PUBLICATIONS.md, "How a page opens"): `publication.json`, then
/// the snapshot, or a private page's sealed block and catalog. The only
/// requests a publication makes before its explorer opens.
class PublicationSource {
  /// In a browser with no [client], the snapshot downloads through the
  /// browser's own progress events (see `snapshot_download.dart`).
  PublicationSource({required Uri pageUri, http.Client? client})
      : _pageUri = pageUri,
        _client = client ?? http.Client(),
        _download = client == null ? browserSnapshotDownload : null;

  final Uri _pageUri;
  final http.Client _client;
  final SnapshotDownload? _download;

  /// Throws [PublicationSourceException].
  Future<String> readSettings(String path) async {
    final response = await _get(path);
    // Always UTF-8, as JSON is. `body` decodes a Content-Type without a
    // charset, which is how gateways serve it, as Latin-1, and a title like
    // "Phil’s Archive" came out garbled.
    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException catch (e) {
      throw PublicationSourceException(
          _resolve(path), 'not UTF-8: ${e.message}');
    }
  }

  /// The snapshot's bytes, reporting each chunk as it arrives. `total` is null
  /// when the gateway does not say how large the body is, which it does not
  /// when it sends the body compressed.
  ///
  /// Throws [PublicationSourceException].
  Future<Uint8List> readSnapshot(
    String path, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final uri = _resolve(path);
    final download = _download;
    if (download != null) {
      try {
        return await download(uri, onProgress ?? (_, __) {});
      } catch (e) {
        throw PublicationSourceException(uri, '$e');
      }
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(http.Request('GET', uri));
    } catch (e) {
      throw PublicationSourceException(uri, 'request failed: $e');
    }
    if (response.statusCode != 200) {
      throw PublicationSourceException(uri, 'status ${response.statusCode}');
    }

    final total = response.contentLength;
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        onProgress?.call(bytes.length, total);
      }
    } catch (e) {
      throw PublicationSourceException(uri, 'body broke off: $e');
    }
    return bytes.takeBytes();
  }

  /// A small part of the page (a private page's sealed block), refused
  /// when it is larger than [maxBytes].
  ///
  /// Throws [PublicationSourceException].
  Future<Uint8List> readPart(String path, {required int maxBytes}) async {
    final uri = _resolve(path);
    final http.StreamedResponse response;
    try {
      response = await _client.send(http.Request('GET', uri));
    } catch (e) {
      throw PublicationSourceException(uri, 'request failed: $e');
    }
    if (response.statusCode != 200) {
      throw PublicationSourceException(uri, 'status ${response.statusCode}');
    }
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      throw PublicationPartTooLarge(uri, maxBytes);
    }
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) {
          throw PublicationPartTooLarge(uri, maxBytes);
        }
      }
    } on PublicationSourceException {
      rethrow;
    } catch (e) {
      throw PublicationSourceException(uri, 'body broke off: $e');
    }
    return bytes.takeBytes();
  }

  Future<http.Response> _get(String path) async {
    final uri = _resolve(path);
    final http.Response response;
    try {
      response = await _client.get(uri);
    } catch (e) {
      throw PublicationSourceException(uri, 'request failed: $e');
    }
    if (response.statusCode != 200) {
      throw PublicationSourceException(uri, 'status ${response.statusCode}');
    }
    return response;
  }

  /// Relative to the page, which is the manifest's index. Resolving a relative
  /// path drops the page's query and fragment, where the app's routes live
  /// (hash routing).
  Uri _resolve(String path) => _pageUri.resolve(path);
}

/// A part of the page larger than any page may have: the page is broken,
/// and reading it again won't help.
class PublicationPartTooLarge extends PublicationSourceException {
  PublicationPartTooLarge(Uri uri, int maxBytes)
      : super(uri, 'larger than $maxBytes bytes');
}

class PublicationSourceException implements Exception {
  const PublicationSourceException(this.uri, this.reason);

  final Uri uri;
  final String reason;

  @override
  String toString() => 'PublicationSourceException($uri): $reason';
}

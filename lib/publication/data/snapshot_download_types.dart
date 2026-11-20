import 'dart:typed_data';

/// A snapshot's bytes and the value of the response header asked for.
typedef SnapshotDownloaded = ({Uint8List bytes, String? header});

/// See `snapshot_download.dart`.
typedef SnapshotDownload = Future<SnapshotDownloaded> Function(
  Uri uri,
  void Function(int received, int? total) onProgress, {
  required int maxBytes,
  required String header,
});

class SnapshotDownloadException implements Exception {
  const SnapshotDownloadException(this.status);

  /// The HTTP status, or 0 or null when there was no response.
  final int? status;

  @override
  String toString() => 'status $status';
}

/// The body was larger than the download allows.
class SnapshotTooLarge implements Exception {
  const SnapshotTooLarge();

  @override
  String toString() => 'too large';
}

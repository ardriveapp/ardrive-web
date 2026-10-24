import 'dart:typed_data';

/// See `snapshot_download.dart`.
typedef SnapshotDownload = Future<Uint8List> Function(
  Uri uri,
  void Function(int received, int? total) onProgress,
);

const SnapshotDownload? browserSnapshotDownload = null;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// See `snapshot_download.dart`.
typedef SnapshotDownload = Future<Uint8List> Function(
  Uri uri,
  void Function(int received, int? total) onProgress,
);

/// The browser's own progress events. `total` is null when the gateway does
/// not say how large the body is. Fails with the request's status, or with
/// none when the request never completed.
const SnapshotDownload browserSnapshotDownload = _download;

Future<Uint8List> _download(
  Uri uri,
  void Function(int received, int? total) onProgress,
) async {
  final html.HttpRequest request;
  try {
    request = await html.HttpRequest.request(
      uri.toString(),
      responseType: 'arraybuffer',
      onProgress: (event) => onProgress(
        event.loaded ?? 0,
        event.lengthComputable ? event.total : null,
      ),
    );
  } on html.ProgressEvent catch (event) {
    final status = (event.target as html.HttpRequest?)?.status;
    throw SnapshotDownloadException(status);
  }
  // `request` also completes, without a body, on a 304 and some redirects.
  if (request.status != 200) throw SnapshotDownloadException(request.status);
  return (request.response as ByteBuffer).asUint8List();
}

class SnapshotDownloadException implements Exception {
  const SnapshotDownloadException(this.status);

  /// The HTTP status, or 0 or null when there was no response.
  final int? status;

  @override
  String toString() => 'status $status';
}

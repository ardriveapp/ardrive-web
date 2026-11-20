import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'snapshot_download_types.dart';

export 'snapshot_download_types.dart';

/// The browser's own progress events. `total` is null when the gateway does
/// not say how large the body is. Fails with the request's status, or with
/// none when the request never completed. Stops, and throws
/// [SnapshotTooLarge], once more than `maxBytes` have arrived.
const SnapshotDownload browserSnapshotDownload = _download;

Future<SnapshotDownloaded> _download(
  Uri uri,
  void Function(int received, int? total) onProgress, {
  required int maxBytes,
  required String header,
}) {
  final done = Completer<SnapshotDownloaded>();
  final request = html.HttpRequest()
    ..open('GET', uri.toString())
    ..responseType = 'arraybuffer';
  var tooLarge = false;
  request.onProgress.listen((event) {
    if (done.isCompleted || tooLarge) return;
    final loaded = event.loaded ?? 0;
    final total = event.lengthComputable ? event.total : null;
    if (loaded > maxBytes || (total != null && total > maxBytes)) {
      tooLarge = true;
      request.abort();
      return;
    }
    onProgress(loaded, total);
  });
  request.onLoadEnd.listen((_) {
    if (done.isCompleted) return;
    // Anything thrown here would leave the download waiting for ever.
    try {
      if (tooLarge) {
        done.completeError(const SnapshotTooLarge());
        return;
      }
      // A request also ends, without a body, on a 304 and some redirects.
      final response = request.response;
      if (request.status != 200 || response is! ByteBuffer) {
        done.completeError(SnapshotDownloadException(request.status));
        return;
      }
      final bytes = response.asUint8List();
      if (bytes.length > maxBytes) {
        done.completeError(const SnapshotTooLarge());
        return;
      }
      done.complete((bytes: bytes, header: request.getResponseHeader(header)));
    } catch (e) {
      if (!done.isCompleted) done.completeError(e);
    }
  });
  request.send();
  return done.future;
}

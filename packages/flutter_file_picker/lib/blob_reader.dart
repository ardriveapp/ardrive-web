/// Reading a picked file's bytes in the browser. Web only: it uses
/// `dart:html`, so import it only from code that runs on the web.
library blob_reader;

import 'dart:async';
import 'dart:html';
import 'dart:typed_data';

/// A browser read of a file that failed or was stopped.
class BlobReadException implements Exception {
  const BlobReadException(this.name);

  /// The browser's name for what went wrong, such as `NotReadableError`.
  final String name;

  @override
  String toString() => 'BlobReadException: $name';
}

/// Reads [blob] into memory.
///
/// Completes with the bytes, or fails with a [BlobReadException]. A failed
/// read never fires `load`, only `error` and then `loadend`, so a read that
/// waits on `load` alone never ends. That happens when the file changed
/// after it was picked, or when a slow or cloud-synced disk can't serve it
/// (`NotReadableError`).
///
/// [reader] can be reused for the chunks of one file. Tests pass their own
/// to abort it.
Future<Uint8List> readBlobBytes(Blob blob, {FileReader? reader}) {
  final fileReader = reader ?? FileReader();
  final done = Completer<Uint8List>();
  final subscriptions = <StreamSubscription<ProgressEvent>>[];

  void finish(ProgressEvent _) {
    if (done.isCompleted) return;
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    final error = fileReader.error;
    final result = fileReader.result;
    if (error == null && result is Uint8List) {
      done.complete(result);
    } else {
      // An aborted read has no error, and no result either.
      done.completeError(BlobReadException(error?.name ?? 'AbortError'));
    }
  }

  subscriptions
    ..add(fileReader.onLoadEnd.listen(finish))
    ..add(fileReader.onError.listen(finish))
    ..add(fileReader.onAbort.listen(finish));
  try {
    fileReader.readAsArrayBuffer(blob);
  } catch (e) {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    return Future.error(BlobReadException(e.runtimeType.toString()));
  }
  return done.future;
}

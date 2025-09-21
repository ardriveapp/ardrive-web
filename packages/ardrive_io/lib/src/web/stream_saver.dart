// ignore_for_file: depend_on_referenced_packages

@JS('window.streamSaver')
library stream_saver;

import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:js/js_util.dart';

class Promise<T> {}

@JS()
external WritableStream createWriteStream(String filename, [Map options]);

@JS()
class WritableStream {
  external bool get locked;

  external Promise<String> abort(String reason);
  external WritableStreamDefaultWriter getWriter();
  external Promise<void> close();
}

extension WritableStreamFutures on WritableStream {
  Future<String> abortFuture(String reason) => promiseToFuture(abort(reason));
  Future<void> closeFuture() => promiseToFuture(close());
}

@JS()
class WritableStreamDefaultWriter {
  external Promise<void> get closed;
  external int get desiredSize;
  external Promise<void> get ready;

  external Promise<void> write(Uint8List data);
  external void abort();
  external void releaseLock();
  external Promise<void> close();
}

extension WritableStreamDefaultWriterFutures on WritableStreamDefaultWriter {
  Future<void> get closedFuture => promiseToFuture(closed);
  Future<void> get readyFuture => promiseToFuture(ready);

  Future<void> writeFuture(Uint8List data) => promiseToFuture(write(data));
  Future<void> closeFuture() => promiseToFuture(close());
}

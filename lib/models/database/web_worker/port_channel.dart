/// A `dart:html` [MessagePort] as a [StreamChannel], for drift's remote
/// protocol between the page and the database worker.
///
/// The same adapter drift uses for its own workers
/// (`package:drift/src/web/channel.dart`), kept here because that one is not
/// part of drift's public API. No Flutter import: the worker compiles this.
library;

// Web-only: reached through the conditional import in database.dart.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'package:stream_channel/stream_channel.dart';

extension DatabasePortChannel on MessagePort {
  StreamChannel<Object?> channel() {
    final controller = StreamChannelController<Object?>();
    onMessage.listen((event) => controller.local.sink.add(event.data));
    controller.local.stream.listen(postMessage, onDone: close);
    return controller.foreign;
  }
}

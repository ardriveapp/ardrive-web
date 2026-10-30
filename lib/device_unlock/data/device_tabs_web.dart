// Web only: reached through the conditional import in device_tabs.dart.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:ardrive/utils/logger.dart';

const _channelName = 'ardrive-device';

html.BroadcastChannel? _channel;

html.BroadcastChannel? _open() {
  try {
    return _channel ??= html.BroadcastChannel(_channelName);
  } catch (e) {
    logger.w('No BroadcastChannel; tabs will not hear each other: $e');
    return null;
  }
}

void post(Map<String, Object?> message) {
  try {
    _open()?.postMessage(message);
  } catch (e) {
    logger.w('Could not tell the other tabs: $e');
  }
}

void listen(void Function(Object? data) onMessage) {
  _open()?.onMessage.listen((event) => onMessage(event.data));
}

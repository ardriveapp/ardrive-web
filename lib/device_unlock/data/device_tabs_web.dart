// Web only: reached through the conditional import in device_tabs.dart.
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:ardrive/utils/logger.dart';
import 'package:flutter/foundation.dart';

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

void post(Map<String, Object?> message) => postOn(_open(), message);

void listen(void Function(Object? data) onMessage) =>
    listenOn(_open(), onMessage);

/// Sends [message] as JSON text. `postMessage` can't clone a Dart map in a
/// release build (a `DataCloneError`), so a message sent as one never reached
/// another tab.
@visibleForTesting
void postOn(html.BroadcastChannel? channel, Map<String, Object?> message) {
  try {
    channel?.postMessage(jsonEncode(message));
  } catch (e) {
    logger.w('Could not tell the other tabs: $e');
  }
}

@visibleForTesting
void listenOn(
  html.BroadcastChannel? channel,
  void Function(Object? data) onMessage,
) {
  channel?.onMessage
      .listen((event) => onMessage(decodeMessageData(event.data)));
}

/// JSON text, decoded. Anything else, such as an object from an older tab,
/// is handed on as it came, for the caller to accept or ignore.
@visibleForTesting
Object? decodeMessageData(Object? data) {
  if (data is! String) return data;
  try {
    return jsonDecode(data);
  } on FormatException {
    return null;
  }
}

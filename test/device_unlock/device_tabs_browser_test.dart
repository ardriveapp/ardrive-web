// Two tabs' BroadcastChannels on one page: a channel never hears itself, but
// a second channel of the same name does, exactly as another tab would.
@TestOn('browser')
library;

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:ardrive/device_unlock/data/device_tabs.dart';
import 'package:ardrive/device_unlock/data/device_tabs_web.dart' as web;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late html.BroadcastChannel otherTab;

  setUp(() => otherTab = html.BroadcastChannel('ardrive-device'));
  tearDown(() => otherTab.close());

  test('what this tab announces reaches another tab', () async {
    final received = Completer<Object?>();
    web.listenOn(otherTab, (data) {
      if (!received.isCompleted) received.complete(data);
    });

    DeviceTabs().announceForgotten(['drive-a', 'drive-b']);

    expect(
      await received.future.timeout(const Duration(seconds: 5)),
      {
        'type': 'forgotten',
        'driveIds': ['drive-a', 'drive-b'],
      },
    );
  });

  test('sign-out from another tab arrives as a message', () async {
    final tabs = DeviceTabs();
    final message = tabs.messages.first;

    web.postOn(otherTab, {'type': 'signed-out'});

    expect(
      await message.timeout(const Duration(seconds: 5)),
      isA<SignedOutInAnotherTab>(),
    );
  });

  test('Forget from another tab arrives with its drive IDs', () async {
    final tabs = DeviceTabs();
    final message = tabs.messages.first;

    web.postOn(otherTab, {
      'type': 'forgotten',
      'driveIds': ['drive-a'],
    });

    final forgotten = await message.timeout(const Duration(seconds: 5));
    expect(forgotten, isA<ForgottenInAnotherTab>());
    expect((forgotten as ForgottenInAnotherTab).driveIds, ['drive-a']);
  });

  test('text that is not JSON is ignored, not thrown', () {
    expect(web.decodeMessageData('not json'), isNull);
    expect(
        web.decodeMessageData('{"type":"signed-out"}'), {'type': 'signed-out'});
  });
}

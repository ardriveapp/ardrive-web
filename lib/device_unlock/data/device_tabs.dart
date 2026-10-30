import 'dart:async';

import 'device_tabs_stub.dart' if (dart.library.html) 'device_tabs_web.dart'
    as implementation;

/// What one ArDrive tab tells the others in this browser.
sealed class DeviceTabsMessage {
  const DeviceTabsMessage();
}

/// Someone signed out in another tab: this device keeps nothing of the
/// account, so every tab signs out too.
class SignedOutInAnotherTab extends DeviceTabsMessage {
  const SignedOutInAnotherTab();
}

/// "Forget on this device" was used in another tab for [driveIds].
class ForgottenInAnotherTab extends DeviceTabsMessage {
  const ForgottenInAnotherTab(this.driveIds);

  final List<String> driveIds;
}

/// The other ArDrive tabs in this browser.
///
/// One tab owns the database (the `ardrive-database` Web Lock); the others
/// work on a session copy whose writes are lost when they close. Sign-out and
/// "Forget on this device" must not be lost that way, so a tab announces
/// them, and the owner applies them to the database that lasts. Messages
/// carry no secrets: a drive ID is not one.
///
/// Off the web there is one window, and nothing is sent.
class DeviceTabs {
  DeviceTabs();

  static final DeviceTabs instance = DeviceTabs();

  final _messages = StreamController<DeviceTabsMessage>.broadcast();
  bool _listening = false;

  /// What other tabs say. Never what this tab said.
  Stream<DeviceTabsMessage> get messages {
    if (!_listening) {
      _listening = true;
      implementation.listen((data) {
        final message = _decode(data);
        if (message != null) _messages.add(message);
      });
    }
    return _messages.stream;
  }

  void announceSignedOut() => implementation.post({'type': 'signed-out'});

  void announceForgotten(List<String> driveIds) {
    if (driveIds.isEmpty) return;
    implementation.post({'type': 'forgotten', 'driveIds': driveIds});
  }

  static DeviceTabsMessage? _decode(Object? data) {
    if (data is! Map) return null;
    switch (data['type']) {
      case 'signed-out':
        return const SignedOutInAnotherTab();
      case 'forgotten':
        final ids = data['driveIds'];
        if (ids is! List) return null;
        return ForgottenInAnotherTab([
          for (final id in ids)
            if (id is String) id,
        ]);
    }
    return null;
  }
}

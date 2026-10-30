import 'dart:async';

import 'implementations/html_web.dart'
    if (dart.library.io) 'implementations/html_stub.dart' as implementation;

class TabVisibilitySingleton {
  static final TabVisibilitySingleton _singleton =
      TabVisibilitySingleton._internal();

  factory TabVisibilitySingleton() {
    return _singleton;
  }

  TabVisibilitySingleton._internal();

  bool isTabFocused() => implementation.isTabFocused();

  Future<void> onTabGetsFocusedFuture(Future Function() onFocus) =>
      implementation.onTabGetsFocusedFuture(onFocus);

  StreamSubscription onTabGetsFocused(Function onFocus) =>
      implementation.onTabGetsFocused(onFocus);

  /// True each time the tab gets focus back or becomes visible again, as
  /// when a browser extension's window closes; false each time it loses
  /// focus or is hidden. Never fires off the web.
  Stream<bool> onTabFocusChanged() => implementation.onTabFocusChanged();
}

// TODO: Move this code to the arconnect package.
Function() onArConnectWalletSwitch(Function onWalletSwitch) =>
    implementation.onWalletSwitch(onWalletSwitch);

/// Calls [onWalletSwitch] with the address Wander switched to each time it
/// says so (its `walletSwitch` event), or null when it gives none, as when a
/// page disconnects. Returns what stops listening.
Function() onArConnectWalletSwitchTo(
  void Function(String? address) onWalletSwitch,
) =>
    implementation.onWalletSwitchTo(onWalletSwitch);

void triggerHTMLPageReload() => implementation.reload();

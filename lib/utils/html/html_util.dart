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

  Future<void> onTabGetsFocusedFuture(FutureOr<Function> onFocus) async =>
      implementation.onTabGetsFocusedFuture(onFocus);

  void onTabGetsFocused(Function onFocus) =>
      implementation.onTabGetsFocused(onFocus);

  Future<void> closeVisibilityChangeStream() =>
      implementation.closeVisibilityChangeStream();
}

void onArConnectWalletSwitch(Function onWalletSwitch) =>
    implementation.onWalletSwitch(onWalletSwitch);

void triggerHTMLPageReload() => implementation.reload();

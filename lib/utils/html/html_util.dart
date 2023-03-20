import 'dart:async';

import 'implementations/html_web.dart'
    if (dart.library.io) 'implementations/html_stub.dart' as implementation;

class TabVisibilitySingleton {
  static final TabVisibilitySingleton _singleton =
      TabVisibilitySingleton._internal();

  /// TODO: Cancel these subscriptions
  late StreamSubscription _onBlurSubscription;
  late StreamSubscription _onFocusSubscription;

  bool _isFocused = true;

  factory TabVisibilitySingleton() {
    return _singleton;
  }

  TabVisibilitySingleton._internal() {
    _onBlurSubscription = implementation.onTabFocused(() {
      print('[TabVisibilitySingleton] Tab focused');
      _isFocused = true;
    });
    _onFocusSubscription = implementation.onTabBlurred(() {
      print('[TabVisibilitySingleton] Tab blurred');
      _isFocused = false;
    });
  }

  bool isTabVisible() => implementation.isTabVisible();

  bool isTabFocused() => _isFocused;

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

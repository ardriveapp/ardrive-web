import 'dart:async';

import 'implementations/html_web.dart'
    if (dart.library.io) 'implementations/html_stub.dart' as implementation;

class TabVisibilitySingleton {
  static final TabVisibilitySingleton _singleton =
      TabVisibilitySingleton._internal();

  /// TODO: Cancel these subscriptions
  late StreamSubscription _onBlurSubscrition;
  late StreamSubscription _onFocusSubscrition;

  bool _isFocused = false;

  factory TabVisibilitySingleton() {
    return _singleton;
  }

  TabVisibilitySingleton._internal() {
    _onBlurSubscrition = implementation.onTabFocuses(() {
      print('[TabVisibilitySingleton] Tab focused');
      _isFocused = true;
    });
    _onFocusSubscrition = implementation.onTabBlurs(() {
      print('[TabVisibilitySingleton] Tab blurred');
      _isFocused = false;
    });

    print('[TabVisibilitySingleton] Tab Visibility Singleton initialized');
  }

  bool isTabFocused() => _isFocused;

  Future<void> onTabGetsFocusedFuture(FutureOr<dynamic> onFocus) =>
      implementation.onTabGetsFocusedFuture(onFocus);

  void onTabGetsFocused(Function onFocus) =>
      implementation.onTabGetsFocused(onFocus);

  Future<void> closeVisibilityChangeStream() =>
      implementation.closeVisibilityChangeStream();
}

void onArConnectWalletSwitch(Function onWalletSwitch) =>
    implementation.onWalletSwitch(onWalletSwitch);

void triggerHTMLPageReload() => implementation.reload();

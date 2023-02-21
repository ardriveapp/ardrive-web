import 'dart:async';

import 'implementations/html_web.dart'
    if (dart.library.io) 'implementations/html_stub.dart' as implementation;

bool isTabFocused() => implementation.isTabFocused();

Future<void> onTabGetsFocusedFuture(FutureOr<Function> onFocus) async =>
    implementation.onTabGetsFocusedFuture(onFocus);

void onTabGetsFocused(Function onFocus) =>
    implementation.onTabGetsFocused(onFocus);

void onArConnectWalletSwitch(Function onWalletSwitch) =>
    implementation.onWalletSwitch(onWalletSwitch);

void triggerHTMLPageReload() => implementation.reload();

Future<void> closeVisibilityChangeStream() =>
    implementation.closeVisibilityChangeStream();

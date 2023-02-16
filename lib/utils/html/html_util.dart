import 'dart:async';

import 'implementations/html_web.dart'
    if (dart.library.io) 'implementations/html_stub.dart' as implementation;

bool isBrowserTabHidden() => implementation.isTabHidden();

Future<void> whenBrowserTabIsUnhiddenFuture(FutureOr<Function> onShow) async =>
    implementation.whenTabIsUnhiddenFuture(onShow);

void whenBrowserTabIsUnhidden(Function onShow) =>
    implementation.whenTabIsUnhidden(onShow);

void onArConnectWalletSwitch(Function onWalletSwitch) =>
    implementation.onWalletSwitch(onWalletSwitch);

void triggerHTMLPageReload() => implementation.reload();

Future<void> closeVisibilityChangeStream() =>
    implementation.closeVisibilityChangeStream();

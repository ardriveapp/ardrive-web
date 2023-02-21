import 'dart:async';

import 'package:universal_html/html.dart';

bool isTabFocused() {
  return window.document.visibilityState == 'visible';
}

late StreamSubscription _onVisibilityChangeStream;

Future<void> onTabGetsFocusedFuture(FutureOr<Function> onFocus) async {
  final completer = Completer<void>();
  _onVisibilityChangeStream = document.onVisibilityChange.listen((event) async {
    if (isTabFocused()) {
      await onFocus;
      await closeVisibilityChangeStream();
      completer.complete(); // resolve the completer when onFocus completes
    }
  });
  await completer.future; // wait for the completer to be resolved
}

void onTabGetsFocused(Function onFocus) {
  _onVisibilityChangeStream = document.onVisibilityChange.listen((event) {
    if (isTabFocused()) {
      onFocus();
    }
  });
}

Future<void> closeVisibilityChangeStream() async =>
    await _onVisibilityChangeStream.cancel();

void onWalletSwitch(Function onWalletSwitch) {
  window.addEventListener('walletSwitch', (event) {
    onWalletSwitch();
  });
}

void reload() {
  window.location.reload();
}

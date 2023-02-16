import 'dart:async';

import 'package:universal_html/html.dart';

bool isTabHidden() {
  return window.document.visibilityState != 'visible';
}

late StreamSubscription _onVisibilityChangeStream;

Future<void> whenTabIsUnhiddenFuture(FutureOr<Function> onShow) async {
  final completer = Completer<void>();
  _onVisibilityChangeStream = document.onVisibilityChange.listen((event) async {
    if (!isTabHidden()) {
      await onShow;
      completer.complete(); // resolve the completer when onShow completes
    }
  });
  await completer.future; // wait for the completer to be resolved
}

void whenTabIsUnhidden(Function onShow) {
  _onVisibilityChangeStream = document.onVisibilityChange.listen((event) {
    if (!isTabHidden()) {
      onShow();
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

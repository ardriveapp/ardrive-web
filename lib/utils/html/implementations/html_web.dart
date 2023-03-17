import 'dart:async';

import 'package:universal_html/html.dart';

bool isTabFocused() {
  return window.document.visibilityState == 'visible';
}

StreamSubscription? _onVisibilityChangeStream;

Future<void> onTabGetsFocusedFuture(FutureOr<dynamic> onFocus) async {
  final completer = Completer<void>();
  final onVisibilityChangeStream = document.onVisibilityChange.listen(
    (event) async {
      if (isTabFocused()) {
        print('Tab is focused');
        await onFocus;
        print('onFocus completed');
        completer.complete(); // resolve the completer when onFocus completes
      }
    },
  );
  await completer.future; // wait for the completer to be resolved
  await onVisibilityChangeStream.cancel(); // cancel the stream
}

void onTabGetsFocused(Function onFocus) {
  _onVisibilityChangeStream = document.onVisibilityChange.listen((event) {
    if (isTabFocused()) {
      onFocus();
    }
  });
}

Future<void> closeVisibilityChangeStream() async =>
    await _onVisibilityChangeStream?.cancel();

void onWalletSwitch(Function onWalletSwitch) {
  window.addEventListener('walletSwitch', (event) {
    onWalletSwitch();
  });
}

void reload() {
  window.location.reload();
}

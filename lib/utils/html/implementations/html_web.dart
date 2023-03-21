import 'dart:async';

import 'package:universal_html/html.dart';

bool isTabVisible() {
  return window.document.visibilityState == 'visible';
}

late StreamSubscription _onVisibilityChangeStream;

Future<void> onTabGetsFocusedFuture(FutureOr<Function> onFocus) async {
  final completer = Completer<void>();
  final onVisibilityChangeStream = onTabFocused((event) async {
    await onFocus;
    completer.complete(); // resolve the completer when onFocus completes
  });
  await completer.future; // wait for the completer to be resolved
  await onVisibilityChangeStream.cancel(); // cancel the stream subscription
}

StreamSubscription onTabBlurred(Function onBlur) {
  final onVisibilityChangeStream = window.onBlur.listen(
    (event) {
      print('Tab went blurred');
      onBlur();
    },
    cancelOnError: false,
  );
  return onVisibilityChangeStream;
}

StreamSubscription onTabFocused(Function onFocus) {
  final onVisibilityChangeStream = window.onFocus.listen(
    (event) {
      print('Tab went focused');
      onFocus();
    },
    cancelOnError: false,
  );
  return onVisibilityChangeStream;
}

void onTabGetsFocused(Function onFocus) {
  _onVisibilityChangeStream = onTabFocused((event) {
    onFocus();
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

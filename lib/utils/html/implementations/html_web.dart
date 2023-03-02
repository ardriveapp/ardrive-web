import 'dart:async';

import 'package:universal_html/html.dart';

bool isTabFocused() {
  return window.document.visibilityState == 'visible';
}

late StreamSubscription _onVisibilityChangeStream;

Future<StreamSubscription?> onTabGetsFocusedFuture(
  FutureOr<Function> onFocus,
  bool periodical,
) async {
  final completer = Completer<void>();
  final onVisibilityChangeStream =
      document.onVisibilityChange.listen((event) async {
    if (isTabFocused()) {
      await onFocus;
      await closeVisibilityChangeStream();
      completer.complete(); // resolve the completer when onFocus completes
    }
  });
  await completer.future; // wait for the completer to be resolved

  if (!periodical) {
    await onVisibilityChangeStream.cancel();
    return null;
  }

  return onVisibilityChangeStream;
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

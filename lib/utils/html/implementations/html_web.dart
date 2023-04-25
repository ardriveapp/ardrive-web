import 'dart:async';

import 'package:ardrive/services/arconnect/is_document_focused.dart';
import 'package:universal_html/html.dart';

bool isTabFocused() {
  return isDocumentFocused();
}

bool isTabVisible() {
  return window.document.visibilityState == 'visible';
}

late StreamSubscription _onVisibilityChangeStream;

Future<void> onTabGetsVisibleFuture(FutureOr<Function> onFocus) async {
  final completer = Completer<void>();
  _onVisibilityChangeStream = document.onVisibilityChange.listen((event) async {
    if (isTabVisible()) {
      await onFocus;
      await closeVisibilityChangeStream();
      completer.complete(); // resolve the completer when onFocus completes
    }
  });
  await completer.future; // wait for the completer to be resolved
}

void onTabGetsVisible(Function onFocus) {
  _onVisibilityChangeStream = document.onVisibilityChange.listen((event) {
    if (isTabVisible()) {
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

import 'dart:async';

import 'package:ardrive_utils/src/html/is_document_focused.dart';
import 'package:universal_html/html.dart';

bool isTabFocused() {
  return isDocumentFocused();
}

Future<void> onTabGetsFocusedFuture(Future Function() onFocus) async {
  final completer = Completer<void>();
  final subscription = onTabGetsFocused(() async {
    await onFocus();
    completer.complete();
  });
  await completer.future; // wait for the completer to be resolved
  await subscription.cancel();
}

StreamSubscription<Event> onTabGetsFocused(Function onFocus) {
  final subscription = window.onFocus.listen(
    (event) {
      onFocus();
    },
  );
  return subscription;
}

Function() onWalletSwitch(Function onWalletSwitch) {
  window.addEventListener('walletSwitch', (event) {
    onWalletSwitch();
  });

  return () {
    window.removeEventListener('walletSwitch', (event) {
      onWalletSwitch();
    });
  };
}

void reload() {
  window.location.reload();
}

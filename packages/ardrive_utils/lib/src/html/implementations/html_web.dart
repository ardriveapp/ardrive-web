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

Stream<void> onTabRegainsFocus() {
  StreamSubscription? focus;
  StreamSubscription? visibility;
  late final StreamController<void> controller;
  controller = StreamController<void>(
    onListen: () {
      focus = window.onFocus.listen((_) => controller.add(null));
      visibility = document.onVisibilityChange.listen((_) {
        if (document.visibilityState == 'visible') controller.add(null);
      });
    },
    onCancel: () async {
      await focus?.cancel();
      await visibility?.cancel();
    },
  );
  return controller.stream;
}

Function() onWalletSwitch(Function callback) {
  listener(event) => callback();

  window.addEventListener('walletSwitch', listener);
  return () => window.removeEventListener('walletSwitch', listener);
}

void reload() {
  window.location.reload();
}

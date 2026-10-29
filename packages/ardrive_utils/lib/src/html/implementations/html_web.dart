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

Stream<bool> onTabFocusChanged() {
  StreamSubscription? focus;
  StreamSubscription? blur;
  StreamSubscription? visibility;
  late final StreamController<bool> controller;
  controller = StreamController<bool>(
    onListen: () {
      focus = window.onFocus.listen((_) => controller.add(true));
      blur = window.onBlur.listen((_) => controller.add(false));
      visibility = document.onVisibilityChange.listen((_) {
        controller.add(document.visibilityState == 'visible');
      });
    },
    onCancel: () async {
      await focus?.cancel();
      await blur?.cancel();
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

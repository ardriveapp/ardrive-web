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

StreamSubscription onTabBlurs(Function onBlur) {
  print('Subscribing to tab blur event');
  // window.addEventListener('blur', (event) {
  //   print('Tab went blurred');
  //   onBlur();
  // });
  final onVisibilityChangeStream = window.onBlur.listen(
    (event) {
      print('Tab went blurred');
      onBlur();
    },
    onError: (err) {
      print('Tab went blurred - ERROR $err');
    },
    onDone: () {
      print('Tab went blurred - DONE');
    },
    cancelOnError: false,
  );
  return onVisibilityChangeStream;
}

StreamSubscription onTabFocuses(Function onFocus) {
  print('Subscribing to tab focus event');
  // window.addEventListener('focus', (event) {
  //   print('Tab went focused');
  //   onFocus();
  // });
  final onVisibilityChangeStream = window.onFocus.listen(
    (event) {
      print('Tab went focused');
      onFocus();
    },
    onError: (err) {
      print('Tab went focused - ERROR $err');
    },
    onDone: () {
      print('Tab went focused - DONE');
    },
    cancelOnError: false,
  );
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
    await _onVisibilityChangeStream?.cancel();

void onWalletSwitch(Function onWalletSwitch) {
  window.addEventListener('walletSwitch', (event) {
    onWalletSwitch();
  });
}

void reload() {
  window.location.reload();
}

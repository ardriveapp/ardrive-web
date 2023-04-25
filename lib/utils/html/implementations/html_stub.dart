import 'dart:async';

bool isTabFocused() {
  return true;
}

Future<void> onTabGetsFocusedFuture(FutureOr<Function> onFocus) async {
  return;
}

StreamSubscription onTabGetsFocused(Function onFocus) {
  const emptyStream = Stream.empty();
  return emptyStream.listen((event) {});
}

void onWalletSwitch(Function onSwitch) {
  return;
}

void reload() {
  return;
}

Future<void> closeVisibilityChangeStream() async {}

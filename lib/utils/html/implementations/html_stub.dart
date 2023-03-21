import 'dart:async';

bool isTabVisible() {
  return true;
}

Future<void> onTabGetsFocusedFuture(FutureOr<Function> onFocus) async {
  return;
}

StreamSubscription onTabBlurred(Function onBlur) {
  const stubStream = Stream.empty();
  return stubStream.listen((event) {});
}

StreamSubscription onTabFocused(Function onFocus) {
  const stubStream = Stream.empty();
  return stubStream.listen((event) {});
}

void onTabGetsFocused(Function onFocus) {
  return;
}

void onWalletSwitch(Function onSwitch) {
  return;
}

void reload() {
  return;
}

Future<void> closeVisibilityChangeStream() async {}

import 'dart:async';

bool isTabFocused() {
  return true;
}

Future<void> onTabGetsFocusedFuture(FutureOr<Function> onFocus) async {
  return;
}

void onTabGetsFocused(Function onFocus) {
  return;
}

StreamSubscription<dynamic> onTabBlurs(Function onBlur) {
  const stubStream = Stream<dynamic>.empty();
  return stubStream.listen((_) => onBlur());
}

StreamSubscription<dynamic> onTabFocuses(Function onFocus) {
  const stubStream = Stream<dynamic>.empty();
  return stubStream.listen((_) => onFocus());
}

void onWalletSwitch(Function onSwitch) {
  return;
}

void reload() {
  return;
}

Future<void> closeVisibilityChangeStream() async {}

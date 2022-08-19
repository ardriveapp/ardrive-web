// import 'dart:html';

import 'dart:async';

bool isTabHidden() {
  //throw UnimplementedError();
  // return window.document.visibilityState != 'visible';
  return false;
}

late StreamSubscription _onVisibilityChangeStream;

void whenTabIsUnhidden(Function onShow) {
  //throw UnimplementedError();
}

Future<void> closeVisibilityChangeStream() async =>
    await _onVisibilityChangeStream.cancel();

void refreshPageAtInterval(Duration duration) {
  //throw UnimplementedError();
}

void onWalletSwitch(Function onWalletSwitch) {
  //throw UnimplementedError();
}

void reload() {
  //throw UnimplementedError();
}

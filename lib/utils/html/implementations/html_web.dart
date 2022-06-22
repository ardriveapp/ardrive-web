import 'dart:async';
import 'dart:html';

bool isTabHidden() {
  return window.document.visibilityState != 'visible';
}

late StreamSubscription _onVisibilityChangeStream;

void whenTabIsUnhidden(Function onShow) {
  _onVisibilityChangeStream = document.onVisibilityChange.listen((event) {
    print('listening visibility change ${event.toString()}');
    if (!isTabHidden()) onShow();
  });
}

Future<void> closeVisibilityChangeStream() async =>
    await _onVisibilityChangeStream.cancel();

void refreshPageAtInterval(Duration duration) {
  Future.delayed(duration, () {
    window.location.reload();
  });
}

void onWalletSwitch(Function onWalletSwitch) {
  window.addEventListener('walletSwitch', (event) {
    onWalletSwitch();
  });
}

void reload() {
  window.location.reload();
}

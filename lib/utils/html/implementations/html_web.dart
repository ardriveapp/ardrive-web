import 'dart:html';

bool isTabHidden() {
  return window.document.visibilityState != 'visible';
}

void whenTabIsUnhidden(Function onShow) {
  document.addEventListener('visibilitychange', (event) {
    if (document.visibilityState != 'hidden') {
      onShow();
    }
  });
}

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

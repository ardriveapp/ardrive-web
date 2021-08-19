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

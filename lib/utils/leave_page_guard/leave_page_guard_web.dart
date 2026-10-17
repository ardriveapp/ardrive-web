// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

final _holders = <Object>{};
StreamSubscription<html.Event>? _beforeUnload;

/// Holds the leave-page guard for [holder].
void holdLeavePageGuard(Object holder) {
  _holders.add(holder);
  _beforeUnload ??= html.window.onBeforeUnload.listen((event) {
    // Both are needed for every browser to ask. Browsers that go by
    // returnValue only ask when it is not empty; none of them show the text.
    event.preventDefault();
    if (event is html.BeforeUnloadEvent) {
      event.returnValue = 'Your upload is still in progress.';
    }
  });
}

/// Releases [holder]'s hold on the leave-page guard.
void releaseLeavePageGuard(Object holder) {
  _holders.remove(holder);
  if (_holders.isEmpty) {
    _beforeUnload?.cancel();
    _beforeUnload = null;
  }
}

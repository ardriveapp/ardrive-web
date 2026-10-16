// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

final _holders = <Object>{};
StreamSubscription<html.Event>? _beforeUnload;

/// Holds the leave-page guard for [holder].
void holdLeavePageGuard(Object holder) {
  _holders.add(holder);
  _beforeUnload ??= html.window.onBeforeUnload.listen((event) {
    // Both are needed for every browser to ask; the text is not shown.
    event.preventDefault();
    if (event is html.BeforeUnloadEvent) event.returnValue = '';
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

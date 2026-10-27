// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

var _watching = false;
var _leaving = false;
Timer? _cancelled;

/// Starts watching for the page leaving.
void watchPageLeaving() {
  if (_watching) return;
  _watching = true;
  html.window.addEventListener('beforeunload', (_) {
    _leaving = true;
    // A leave the reader cancels ("Stay") fires no other event, so the flag
    // clears itself unless `pagehide` confirms the page really went.
    _cancelled?.cancel();
    _cancelled = Timer(const Duration(seconds: 2), () => _leaving = false);
  });
  html.window.addEventListener('pagehide', (_) {
    _cancelled?.cancel();
    _leaving = true;
  });
  // Back from the browser's page cache.
  html.window.addEventListener('pageshow', (_) {
    _cancelled?.cancel();
    _leaving = false;
  });
}

/// Whether the page is being closed or reloaded.
bool pageIsLeaving() => _leaving;

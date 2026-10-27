// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

var _watching = false;
var _leaving = false;

/// Starts watching for the page leaving.
void watchPageLeaving() {
  if (_watching) return;
  _watching = true;
  html.window.addEventListener('beforeunload', (_) => _leaving = true);
  html.window.addEventListener('pagehide', (_) => _leaving = true);
  // Back from the browser's page cache, or a leave that was cancelled.
  html.window.addEventListener('pageshow', (_) => _leaving = false);
}

/// Whether the page is being closed or reloaded.
bool pageIsLeaving() => _leaving;

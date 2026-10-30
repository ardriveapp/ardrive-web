// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// Safari, and every iOS browser (all of them are WebKit): the engine's own
/// test is the same vendor string.
bool get browserIsWebKit => (html.window.navigator.vendor).startsWith('Apple');

/// Whether the engine runs on CanvasKit, which sets `window.flutterCanvasKit`
/// when it loads. Otherwise it is the HTML renderer, which draws text with
/// the browser's own engine.
bool get rendererIsCanvasKit =>
    js_util.hasProperty(html.window, 'flutterCanvasKit');

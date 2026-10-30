// ignore_for_file: avoid_web_libraries_in_flutter
@TestOn('browser')
library;

import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter_test/flutter_test.dart';

/// web/js/lazy_loader.js hides AMD's `define` and `require` while it loads a
/// UMD bundle, so the bundle sets its global. Two loads can overlap. When each
/// saved and restored its own copy, the second saved the `undefined` the first
/// had set and put that back last, leaving the page without them.
///
/// Run with `tool/browser_tests.sh`, which serves `web/` on 127.0.0.1:8099.
void main() {
  const webRoot = 'http://127.0.0.1:8099/';

  late Object? originalDefine;
  late Object? originalRequire;

  setUpAll(() async {
    final loader = html.ScriptElement()..src = '${webRoot}js/lazy_loader.js';
    html.document.head!.append(loader);
    await loader.onLoad.first;
  });

  setUp(() {
    originalDefine = js_util.getProperty<Object?>(html.window, 'define');
    originalRequire = js_util.getProperty<Object?>(html.window, 'require');
  });

  tearDown(() {
    js_util.setProperty(html.window, 'define', originalDefine);
    js_util.setProperty(html.window, 'require', originalRequire);
  });

  test('two overlapping loads give define and require back', () async {
    final define = js_util.newObject<Object>();
    final require = js_util.newObject<Object>();
    js_util.setProperty(html.window, 'define', define);
    js_util.setProperty(html.window, 'require', require);

    final lazyLoader = js_util.getProperty<Object>(html.window, 'LazyLoader');
    Future<void> load(String path) => js_util.promiseToFuture<void>(
          js_util.callMethod<Object>(
              lazyLoader, 'loadGlobalScript', ['$webRoot$path']),
        );

    // A small script and a large one, started in that order, so the first
    // to start is the first to finish.
    await Future.wait([
      load('js/is_document_focused.js'),
      load('js/pst.min.js'),
    ]);

    expect(
      identical(js_util.getProperty<Object?>(html.window, 'define'), define),
      isTrue,
    );
    expect(
      identical(js_util.getProperty<Object?>(html.window, 'require'), require),
      isTrue,
    );
  });
}

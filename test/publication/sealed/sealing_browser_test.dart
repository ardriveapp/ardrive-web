// ignore_for_file: avoid_web_libraries_in_flutter
@TestOn('browser')
library;

import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:ardrive/publication/domain/sealed/seal_codec.dart';
import 'package:ardrive/publication/domain/sealed/sealing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sealing_vectors.dart';

/// The browser's Argon2id (the vendored hash-wasm, web/js/hash-wasm) and
/// NFC (String.normalize), and WebCrypto's AES-GCM and HKDF, held to the
/// same vectors as the Dart ones.
///
/// tool/browser_tests.sh serves web/ on 127.0.0.1:8099. The test page is
/// served from elsewhere, so a stand-in LazyLoader loads the real module
/// from there, hiding require.js as the real loadGlobalScript does.
void main() {
  setUpAll(() {
    html.document.head!.append(html.ScriptElement()
      ..text = '''
        window.argon2Loads = 0;
        window.LazyLoader = {
          loadArgon2: function() {
            window.argon2Loads++;
            return new Promise(function(resolve, reject) {
              var define = window.define, require = window.require;
              window.define = undefined; window.require = undefined;
              var s = document.createElement('script');
              s.src = 'http://127.0.0.1:8099/js/hash-wasm/argon2.umd.min.js';
              s.onload = function() { window.define = define; window.require = require; resolve(); };
              s.onerror = function() { window.define = define; window.require = require; reject(new Error('load failed')); };
              document.head.appendChild(s);
            });
          },
        };
      ''');
  });

  test('the module loads once, on first use', () async {
    expect(
        js_util.getProperty<Object?>(js_util.globalThis, 'hashwasm'), isNull);
    final sealing = Sealing();
    const settings = Argon2Settings(m: 8192, t: 1, p: 1);
    final salt = List.filled(16, 1);
    await Future.wait([
      sealing.passwordKek('a', salt: salt, settings: settings),
      sealing.passwordKek('b', salt: salt, settings: settings),
    ]);
    await sealing.passwordKek('c', salt: salt, settings: settings);
    expect(js_util.getProperty<int>(js_util.globalThis, 'argon2Loads'), 1);
  });

  sealingVectorTests();
}

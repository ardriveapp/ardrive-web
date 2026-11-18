// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'seal_codec.dart';
import 'sealing.dart';

/// In the browser: Argon2id from hash-wasm (web/js/hash-wasm, loaded on
/// first use by `LazyLoader.loadArgon2`), and the browser's own NFC.
///
/// Dart's Argon2id compiled to JavaScript takes many seconds at the writer
/// defaults, so there is no fallback to it: when the module can't load,
/// deriving fails and the page can still open by key.
Argon2idKdf argon2id() => _HashWasmArgon2id();

String nfc(String text) =>
    js_util.callMethod<String>(text, 'normalize', ['NFC']);

class _HashWasmArgon2id implements Argon2idKdf {
  static Future<Object>? _module;

  static Future<Object> _load() async {
    var hashwasm = js_util.getProperty<Object?>(js_util.globalThis, 'hashwasm');
    if (hashwasm == null || !js_util.hasProperty(hashwasm, 'argon2id')) {
      final lazyLoader =
          js_util.getProperty<Object?>(js_util.globalThis, 'LazyLoader');
      if (lazyLoader == null) throw StateError('the script loader is missing');
      await js_util.promiseToFuture<void>(
          js_util.callMethod(lazyLoader, 'loadArgon2', []));
      hashwasm = js_util.getProperty<Object?>(js_util.globalThis, 'hashwasm');
    }
    if (hashwasm == null || !js_util.hasProperty(hashwasm, 'argon2id')) {
      throw StateError('Argon2id did not load');
    }
    return hashwasm;
  }

  @override
  Future<Uint8List> derive({
    required List<int> password,
    required List<int> salt,
    required Argon2Settings settings,
  }) async {
    final Object hashwasm;
    try {
      hashwasm = await (_module ??= _load());
    } catch (_) {
      _module = null; // A later attempt may load it.
      rethrow;
    }
    final options = js_util.newObject<Object>();
    js_util.setProperty(options, 'password', Uint8List.fromList(password));
    js_util.setProperty(options, 'salt', Uint8List.fromList(salt));
    js_util.setProperty(options, 'parallelism', settings.p);
    js_util.setProperty(options, 'iterations', settings.t);
    js_util.setProperty(options, 'memorySize', settings.m);
    js_util.setProperty(options, 'hashLength', keyBytes);
    js_util.setProperty(options, 'outputType', 'binary');
    final out = await js_util.promiseToFuture<Uint8List>(
        js_util.callMethod(hashwasm, 'argon2id', [options]));
    return Uint8List.fromList(out);
  }
}

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_util' as js_util;

import 'package:js/js.dart';

Future<T> runExclusiveAcrossTabs<T>(String name, Future<T> Function() body) {
  final navigator =
      js_util.getProperty<Object?>(js_util.globalThis, 'navigator');
  final locks = navigator == null
      ? null
      : js_util.getProperty<Object?>(navigator, 'locks');
  if (locks == null) return body();

  final result = Completer<T>();
  // Held until [body] settles; its outcome is handed back through [result],
  // so the lock's own promise never carries an error.
  final request = js_util.callMethod<Object>(locks, 'request', [
    name,
    allowInterop((Object? _) {
      final done = body().then(result.complete, onError: result.completeError);
      return js_util.callConstructor<Object>(
        js_util.getProperty<Object>(js_util.globalThis, 'Promise'),
        [
          allowInterop((Object resolve, Object _) {
            done.whenComplete(
                () => js_util.callMethod(resolve, 'call', [null]));
          }),
        ],
      );
    }),
  ]);
  js_util.promiseToFuture<Object?>(request).catchError((Object e) {
    if (!result.isCompleted) result.completeError(e);
    return null;
  });
  return result.future;
}

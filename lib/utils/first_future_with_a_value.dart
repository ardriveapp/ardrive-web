import 'dart:async';

class FutureError {
  Object error;
  StackTrace stackTrace;
  FutureError(this.error, this.stackTrace);
}

Future<T> firstWithAValue<T>(Iterable<Future<T>> futures) {
  final completer = Completer<T>.sync();
  final errors = [];

  void onValue(T value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  void onError(Object error, StackTrace stack) {
    errors.add(FutureError(error, stack));
    if (!completer.isCompleted && errors.length == futures.length) {
      completer.completeError(errors);
    }
  }

  for (var future in futures) {
    future.then(onValue, onError: onError);
  }

  return completer.future;
}

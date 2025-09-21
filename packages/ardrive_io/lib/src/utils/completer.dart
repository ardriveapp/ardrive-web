import 'dart:async';

Future<T?> completerMaybe<T>(Completer<T> completer) => 
  completer.isCompleted
    ? completer.future
    : Future.value(null);

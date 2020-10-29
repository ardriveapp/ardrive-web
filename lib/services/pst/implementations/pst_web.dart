@JS('pst')
library pst;

import 'dart:js_util';

import 'package:js/js.dart';

@JS('getWeightedPstHolder')
external Object getWeightedPstHolderPromise();

Future<String> getWeightedPstHolder() {
  var promise = getWeightedPstHolderPromise();
  return promiseToFuture(promise);
}

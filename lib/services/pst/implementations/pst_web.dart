@JS('pst')
library pst;

import 'dart:js_util';

import 'package:js/js.dart';

@JS('getPstFeePercentage')
external Object getPstFeePercentagePromise();

@JS('getWeightedPstHolder')
external Object getWeightedPstHolderPromise();

Future<double> getPstFeePercentage() {
  var promise = getPstFeePercentagePromise();
  return promiseToFuture(promise);
}

Future<String> getWeightedPstHolder() {
  var promise = getWeightedPstHolderPromise();
  return promiseToFuture(promise);
}

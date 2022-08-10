@JS('pst')
library pst;

import 'dart:js_util';

import 'package:ardrive/types/transaction_id.dart';
import 'package:js/js.dart';

@JS('readContractPromise')
external Object _readContractPromise(String contractTxId);

Future<dynamic> readContract(TransactionID contractTxId) {
  final promise = _readContractPromise(contractTxId.toString());
  return promiseToFuture(promise);
}

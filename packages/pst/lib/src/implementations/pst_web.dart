@JS('pst')
library pst;

import 'dart:convert';

import 'package:ardrive_utils/ardrive_utils.dart';
// ignore: depend_on_referenced_packages
import 'package:js/js.dart';
import 'package:universal_html/js_util.dart';

@JS('readContractAsStringPromise')
external Object _readContractAsStringPromise(String contractTxId);

Future<dynamic> readContract(TransactionID contractTxId) async {
  final promise = _readContractAsStringPromise(contractTxId.toString());
  final stringified = await promiseToFuture(promise);

  return jsonDecode(stringified)['state'];
}

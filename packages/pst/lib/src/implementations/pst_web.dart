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
  await _loadPst();

  final promise = _readContractAsStringPromise(contractTxId.toString());
  final stringified = await promiseToFuture(promise);

  return jsonDecode(stringified)['state'];
}

/// Loads pst.min.js (web/js/lazy_loader.js) on first use.
///
/// index.html stopped carrying it in 2.82.0, so nothing else defines
/// `window.pst`: without this the Warp fallback always failed.
Future<void> _loadPst() async {
  final lazyLoader = getProperty(globalThis, 'LazyLoader');
  if (lazyLoader != null) {
    await promiseToFuture(callMethod(lazyLoader, 'loadPst', []));
  }
}

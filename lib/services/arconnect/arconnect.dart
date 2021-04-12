@JS()
library arconnect;

import 'package:js/js.dart';
import 'package:js/js_util.dart';

@JS('loadWallet')
external Map _loadWallet();

Future loadWallet() async {
  final obj = (await promiseToFuture(_loadWallet()));
  print(obj);
}

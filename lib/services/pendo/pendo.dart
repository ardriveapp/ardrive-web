@JS()
library arconnect;

import 'package:js/js.dart';

@JS('initializePendo')
external void initializePendo(String md5OfWalletAddress);

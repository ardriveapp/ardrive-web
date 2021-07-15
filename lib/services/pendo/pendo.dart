@JS()
library pendo;

import 'package:js/js.dart';

@JS('initializePendo')
external void initializePendo(String md5OfWalletAddress);

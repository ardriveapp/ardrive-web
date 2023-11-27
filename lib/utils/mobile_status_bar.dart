import 'package:flutter/services.dart';

abstract class MobileStatusBar {
  static hide() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  static show() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

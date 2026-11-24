import 'package:flutter/services.dart';

abstract class MobileScreenOrientation {
  static void freeUpDependingOnScreenSize() {
    // if (ScreenSize.isSmall) {
    //  blockInPortraitUp();
    // } else {
    //  freeUp();
    // }
    throw UnimplementedError();
  }

  static void freeUp() {
    // SystemChrome.setPreferredOrientations([
    //   DeviceOrientation.portraitUp,
    //   DeviceOrientation.landscapeRight,
    //   DeviceOrientation.landscapeLeft,
    //   DeviceOrientation.portraitDown,
    // ]);
    throw UnimplementedError();
  }

  /// Lets the device turn either way: a full-screen photo, which should
  /// fill a portrait screen as well as a landscape one.
  static void followDevice() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
  }

  static void lockInLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
  }

  static void lockInPortraitUp() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }
}

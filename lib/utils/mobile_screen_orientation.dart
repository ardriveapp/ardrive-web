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

  static void blockInLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
  }

  static void blockInPortraitUp() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }
}

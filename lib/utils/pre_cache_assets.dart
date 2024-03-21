import 'package:ardrive/misc/resources.dart';
import 'package:flutter/material.dart';

void preCacheLoginAssets(BuildContext context) {
  List<String> assetPaths = [
    Resources.images.login.gridImage,
    Resources.images.login.ardriveLoader,
    Resources.images.login.whatIsAKeyfile,
    Resources.images.login.aboutSecurity,
  ];

  for (String assetPath in assetPaths) {
    precacheImage(
      AssetImage(assetPath),
      context,
    );
  }
}

void preCacheOnBoardingAssets(BuildContext context) {
  List<String> assetPaths = [
    Resources.images.login.ardriveLogoOnboarding,
    Resources.images.login.arrowRed,
    Resources.images.login.confetti,
    Resources.images.login.confettiLeft,
    Resources.images.login.confettiRight,
    Resources.images.login.placeholder1,
    Resources.images.login.placeholder2,
  ];

  for (String assetPath in assetPaths) {
    precacheImage(
      AssetImage(assetPath),
      context,
    );
  }
}

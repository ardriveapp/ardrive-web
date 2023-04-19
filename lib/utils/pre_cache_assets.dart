import 'package:ardrive/misc/resources.dart';
import 'package:flutter/material.dart';

void preCacheLoginAssets(BuildContext context) {
  List<String> assetPaths = [
    Resources.images.login.login1,
    Resources.images.login.login2,
    Resources.images.login.login3,
    Resources.images.login.login4,
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
    Resources.images.login.onboarding.onboarding1,
    Resources.images.login.onboarding.onboarding2,
    Resources.images.login.onboarding.onboarding3,
    Resources.images.login.onboarding.onboarding4,
    Resources.images.login.onboarding.onboarding5,
    Resources.images.login.onboarding.onboarding6,
  ];

  for (String assetPath in assetPaths) {
    precacheImage(
      AssetImage(assetPath),
      context,
    );
  }
}

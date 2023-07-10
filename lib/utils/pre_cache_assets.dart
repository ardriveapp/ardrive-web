import 'package:ardrive/misc/resources.dart';
import 'package:flutter/material.dart';

void preCacheLoginAssets(BuildContext context) {
  List<String> assetPaths = [
    Resources.images.login.gridImage,
    Resources.images.login.arconnectLogo,
    Resources.images.login.lattice,
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
  ];

  for (String assetPath in assetPaths) {
    precacheImage(
      AssetImage(assetPath),
      context,
    );
  }
}

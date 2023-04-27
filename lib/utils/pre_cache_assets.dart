import 'package:ardrive/misc/resources.dart';
import 'package:flutter/material.dart';

void preCacheLoginAssets(BuildContext context) {
  List<String> assetPaths = [
    Resources.images.login.gridImage,
    Resources.images.login.arconnectLogo,
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
    Resources.images.login.ardrivePlates1,
    Resources.images.login.ardrivePlates2,
    Resources.images.login.ardrivePlates3,
  ];

  for (String assetPath in assetPaths) {
    precacheImage(
      AssetImage(assetPath),
      context,
    );
  }
}

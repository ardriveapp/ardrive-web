import 'package:ardrive/misc/resources.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

void preCacheLoginAssets(BuildContext context) {
  List<String> assetPaths = [
    Resources.images.login.gridImage,
    Resources.images.login.whatIsAKeyfile,
    Resources.images.login.aboutSecurity,
    Resources.images.login.bentoBox.profile2,
    Resources.images.login.bentoBox.profile3,
    Resources.images.login.bentoBox.profile4,
    Resources.images.login.bentoBox.profile5,
    Resources.images.login.bentoBox.profile6,
    Resources.images.login.bentoBox.dots,
  ];

  List<String> svgAssets = [
    Resources.images.login.bentoBox.bentoBox2DarkMode,
    Resources.images.login.bentoBox.bentoBox2LightMode,
    Resources.images.login.bentoBox.noSubscription,
    Resources.images.login.bentoBox.decentralized,
    Resources.images.login.bentoBox.permanentAccessibleData,
    Resources.images.login.bentoBox.priceCalculator,
    Resources.images.login.bentoBox.dataStorage,
  ];

  for (String assetPath in assetPaths) {
    precacheImage(
      AssetImage(assetPath),
      context,
    );
  }

  if (kIsWeb) {
    for (String svgAsset in svgAssets) {
      precachePicture(
        ExactAssetPicture(SvgPicture.svgStringDecoderBuilder, svgAsset),
        context,
      );
    }
  }
}

void preCacheOnBoardingAssets(BuildContext context) {
  List<String> assetPaths = [
    Resources.images.login.ardriveLogoOnboarding,
    Resources.images.login.arrowRed,
    Resources.images.login.confetti,
    Resources.images.login.confettiLeft,
    Resources.images.login.confettiRight,
  ];

  for (String assetPath in assetPaths) {
    precacheImage(
      AssetImage(assetPath),
      context,
    );
  }
}

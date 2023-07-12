import 'package:ardrive/misc/resources.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

Widget turboLogo(
  BuildContext context, {
  required double height,
}) {
  // TODO: get rid of this conditional - PE-4161
  return SvgPicture.asset(
    ArDriveTheme.of(context).themeData.name == 'dark'
        ? Resources.images.brand.turboWhite
        : Resources.images.brand.turboBlack,
    height: height,
  );
}

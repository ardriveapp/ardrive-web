import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class ArDriveIcon extends StatelessWidget {
  const ArDriveIcon({
    super.key,
    required this.path,
    this.color,
    this.size = 20,
  });

  final String path;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      color: color ?? ArDriveTheme.of(context).themeData.colors.themeFgOnAccent,
      path,
      height: size,
      width: size,
      package: 'ardrive_ui_library',
    );
  }
}

class ArDriveIcons {
  static ArDriveIcon closeIconCircle({double? size}) =>
      const ArDriveIcon(path: 'assets/icons/close_icon_circle.svg');
  static ArDriveIcon closeIcon({double? size}) =>
      const ArDriveIcon(path: 'assets/icons/close_icon.svg');
  static ArDriveIcon uploadCloud({double? size, Color? color}) => ArDriveIcon(
      path: 'assets/icons/cloud_upload.svg', size: size, color: color);
  static ArDriveIcon checkSuccess({double? size, Color? color}) => ArDriveIcon(
      path: 'assets/icons/check_success.svg', size: size, color: color);
  static ArDriveIcon warning({double? size, Color? color}) =>
      ArDriveIcon(path: 'assets/icons/warning.svg', size: size, color: color);
}

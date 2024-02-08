import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class ArDriveIcon extends StatelessWidget {
  const ArDriveIcon({
    super.key,
    this.color,
    this.size = 24,
    required this.icon,
  });

  final double? size;
  final Color? color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color ?? ArDriveTheme.of(context).themeData.colors.themeFgDefault,
    );
  }

  ArDriveIcon copyWith({
    double? size,
    Color? color,
    IconData? icon,
  }) {
    return ArDriveIcon(
      icon: icon ?? this.icon,
      size: size ?? this.size,
      color: color ?? this.color,
    );
  }
}

class ArDriveIcons {
  const ArDriveIcons._();

  static ArDriveIcon iconAddDrive({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.icon_add_drive,
        size: size,
        color: color,
      );

  static ArDriveIcon iconNewFolder1({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.icon_new_folder1,
        size: size,
        color: color,
      );

  static ArDriveIcon iconUploadFolder1({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.icon_upload_folder1,
        size: size,
        color: color,
      );

  static ArDriveIcon iconUploadFiles({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.icon_upload_files,
        size: size,
        color: color,
      );

  static ArDriveIcon iconCreateSnapshot({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.icon_create_snapshot,
        size: size,
        color: color,
      );

  static ArDriveIcon iconAttachDrive({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.icon_attach_drive,
        size: size,
        color: color,
      );

  static ArDriveIcon arconnectIcon1({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.arconnect_icon_1,
        size: size,
        color: color,
      );

  static ArDriveIcon addDrive({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.add_drive,
        size: size,
        color: color,
      );

  static ArDriveIcon arrowLeftFilled({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.arrow_left_filled,
        size: size,
        color: color,
      );

  static ArDriveIcon arrowLeftOutline({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.arrow_left_outline,
        size: size,
        color: color,
      );

  static ArDriveIcon arrowLeft({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.arrow_left,
        size: size,
        color: color,
      );

  static ArDriveIcon arrowRightFilled({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.arrow_right_filled,
        size: size,
        color: color,
      );

  static ArDriveIcon arrowRightOutline({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.arrow_right_outline,
        size: size,
        color: color,
      );

  static ArDriveIcon bullertList({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.bullert_list,
        size: size,
        color: color,
      );

  static ArDriveIcon camera1({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.camera_1,
        size: size,
        color: color,
      );

  static ArDriveIcon camera2({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.camera_2,
        size: size,
        color: color,
      );

  static ArDriveIcon carretDown({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.carret_down,
        size: size,
        color: color,
      );

  static ArDriveIcon carretLeft({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.carret_left,
        size: size,
        color: color,
      );

  static ArDriveIcon carretRight({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.carret_right,
        size: size,
        color: color,
      );

  static ArDriveIcon carretUp({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.carret_up,
        size: size,
        color: color,
      );

  static ArDriveIcon checkCirle({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.check_cirle,
        size: size,
        color: color,
      );

  static ArDriveIcon checkmark({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.checkmark,
        size: size,
        color: color,
      );

  static ArDriveIcon closeCircle({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.close_circle,
        size: size,
        color: color,
      );

  static ArDriveIcon closeRectangle({double? size, Color? color}) =>
      ArDriveIcon(
        icon: ArDriveIconsData.close_rectangle,
        size: size,
        color: color,
      );

  static ArDriveIcon copy({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.copy,
        size: size,
        color: color,
      );

  static ArDriveIcon dots({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.dots,
        size: size,
        color: color,
      );

  static ArDriveIcon download({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.download,
        size: size,
        color: color,
      );

  static ArDriveIcon editFilled({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.edit_filled,
        size: size,
        color: color,
      );

  static ArDriveIcon edit({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.edit,
        size: size,
        color: color,
      );

  static ArDriveIcon fileX({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.file_x,
        size: size,
        color: color,
      );

  static ArDriveIcon file({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.file,
        size: size,
        color: color,
      );

  // file outlined
  static ArDriveIcon fileOutlined({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.file,
        size: size,
        color: color,
      );

  static ArDriveIcon folderFilled({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.folder_filled,
        size: size,
        color: color,
      );

  static ArDriveIcon folderOutline({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.folder_outline,
        size: size,
        color: color,
      );

  static ArDriveIcon upload({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.upload,
        size: size,
        color: color,
      );

  static ArDriveIcon triangle({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.triangle,
        size: size,
        color: color,
      );

  // menu
  static ArDriveIcon menu({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.menu,
        size: size,
        color: color,
      );

  // refresh
  static ArDriveIcon refresh({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.refresh,
        size: size,
        color: color,
      );

  // x
  static ArDriveIcon x({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.x,
        size: size,
        color: color,
      );

  // new window
  static ArDriveIcon newWindow({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.new_window,
        size: size,
        color: color,
      );
  // share
  static ArDriveIcon share({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.share,
        size: size,
        color: color,
      );
  // license
  static ArDriveIcon license({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.license,
        size: size,
        color: color,
      );
  // move
  static ArDriveIcon move({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.move,
        size: size,
        color: color,
      );
  // plus
  static ArDriveIcon plus({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.plus,
        size: size,
        color: color,
      );
  // tournament
  static ArDriveIcon tournament({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.tournament,
        size: size,
        color: color,
      );

  // logout
  static ArDriveIcon logout({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.logout,
        size: size,
        color: color,
      );

  // user
  static ArDriveIcon user({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.user,
        size: size,
        color: color,
      );

  // zip
  static ArDriveIcon zip({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.zip,
        size: size,
        color: color,
      );

  // help
  static ArDriveIcon question({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.question,
        size: size,
        color: color,
      );

  // image
  static ArDriveIcon image({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.image,
        size: size,
        color: color,
      );

  // ivdeo
  static ArDriveIcon video({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.video,
        size: size,
        color: color,
      );

  // music
  static ArDriveIcon music({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.music,
        size: size,
        color: color,
      );

  // info
  static ArDriveIcon info({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.info,
        size: size,
        color: color,
      );
  // kebab menu
  static ArDriveIcon kebabMenu({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.kebab_menu,
        size: size,
        color: color,
      );

  // eye_closed
  static ArDriveIcon eyeClosed({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.eye_closed,
        size: size,
        color: color,
      );

  // eye_open
  static ArDriveIcon eyeOpen({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.eye_open,
        size: size,
        color: color,
      );

  // keypad
  static ArDriveIcon keypad({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.keypad,
        size: size,
        color: color,
      );

  // pin
  static ArDriveIcon pinNoCircle({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.pin_no_circle,
        size: size,
        color: color,
      );

  // pin with circle
  static ArDriveIcon pinWithCircle({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.pin_circle,
        size: size,
        color: color,
      );

  // arrow-download
  static ArDriveIcon arrowDownload({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.arrow_download,
        size: size,
        color: color,
      );

  static ArDriveIcon cloudSync({double? size, Color? color}) => ArDriveIcon(
        icon: Icons.cloud_sync,
        size: size,
        color: color,
      );

  static ArDriveIcon detach({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.detach,
        size: size,
        color: color,
      );

  static ArDriveIcon download2({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.download_2,
        size: size ?? 18,
        color: color,
      );

  static ArDriveIcon manifest({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.manifest_icon_flattened,
        size: size ?? 26,
        color: color,
      );

  static ArDriveIcon gift({double? size, Color? color}) => ArDriveIcon(
        icon: ArDriveIconsData.gift,
        size: size ?? 26,
        color: color,
      );
}

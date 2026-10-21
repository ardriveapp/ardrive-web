import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';

class ArDriveFileIcon extends StatelessWidget {
  final String contentType;
  final String? fileStatus;
  final double size;

  const ArDriveFileIcon({
    super.key,
    required this.contentType,
    this.fileStatus,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: _getIconForContentType(contentType),
          ),
          if (fileStatus != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: FileStatusDot(status: fileStatus!),
            ),
        ],
      ),
    );
  }

  ArDriveIcon _getIconForContentType(String contentType) {
    if (contentType == 'folder') {
      return ArDriveIcons.folderOutline(
        size: size,
      );
    } else if (FileTypeHelper.isZip(contentType)) {
      return ArDriveIcons.zip(
        size: size,
      );
    } else if (FileTypeHelper.isImage(contentType)) {
      return ArDriveIcons.image(
        size: size,
      );
    } else if (FileTypeHelper.isVideo(contentType)) {
      return ArDriveIcons.video(
        size: size,
      );
    } else if (FileTypeHelper.isAudio(contentType)) {
      return ArDriveIcons.music(
        size: size,
      );
    } else if (FileTypeHelper.isDoc(contentType)) {
      return ArDriveIcons.fileOutlined(
        size: size,
      );
    } else if (FileTypeHelper.isCode(contentType)) {
      return ArDriveIcons.fileOutlined(
        size: size,
      );
    } else {
      return ArDriveIcons.fileOutlined(
        size: size,
      );
    }
  }
}

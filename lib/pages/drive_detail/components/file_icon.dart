import 'package:ardrive/models/models.dart';
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
              child: _buildFileStatus(context, fileStatus!),
            ),
        ],
      ),
    );
  }

  Widget _buildFileStatus(BuildContext context, String status) {
    late Color indicatorColor;

    switch (status) {
      case TransactionStatus.pending:
        indicatorColor =
            ArDriveTheme.of(context).themeData.colors.themeWarningFg;
        break;
      case TransactionStatus.confirmed:
        indicatorColor =
            ArDriveTheme.of(context).themeData.colors.themeSuccessFb;
        break;
      case TransactionStatus.failed:
        indicatorColor = ArDriveTheme.of(context).themeData.colors.themeErrorFg;
        break;
      default:
        indicatorColor = Colors.transparent;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: indicatorColor,
        borderRadius: BorderRadius.circular(4),
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

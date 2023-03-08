import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class DriveExplorerItemTile extends TableRowWidget {
  DriveExplorerItemTile({
    required String name,
    required String size,
    required String lastUpdated,
    required String dateCreated,
    required Function() onPressed,
  }) : super(
          [
            Text(
              name,
              style: ArDriveTypography.body.buttonNormalBold(),
            ),
            Text(size, style: ArDriveTypography.body.xSmallRegular()),
            Text(lastUpdated, style: ArDriveTypography.body.captionRegular()),
            Text(dateCreated, style: ArDriveTypography.body.captionRegular()),
          ],
        );
}

class DriveExplorerItemTileLeading extends StatelessWidget {
  const DriveExplorerItemTileLeading({super.key, required this.item});

  final ArDriveDataTableItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8.0),
      child: _buildFileIcon(context),
    );
  }

  Widget _buildFileIcon(BuildContext context) {
    return ArDriveCard(
      width: 30,
      height: 30,
      elevation: 0,
      contentPadding: EdgeInsets.zero,
      content: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: _getIconForContentType(
              item.contentType,
            ),
          ),
          if (item.fileStatusFromTransactions != null)
            Positioned(
              right: 3,
              bottom: 3,
              child: _buildFileStatus(context),
            ),
        ],
      ),
      backgroundColor: ArDriveTheme.of(context).themeData.backgroundColor,
    );
  }

  Widget _buildFileStatus(BuildContext context) {
    late Color indicatorColor;

    switch (item.fileStatusFromTransactions) {
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
    const size = 15.0;

    if (contentType == 'folder') {
      return ArDriveIcons.folderOutlined(
        size: size,
      );
    } else if (contentType == 'application/zip' ||
        contentType == 'application/x-rar-compressed') {
      return ArDriveIcons.fileZip(
        size: size,
      );
    } else if (contentType.startsWith('image/')) {
      return ArDriveIcons.image(
        size: size,
      );
    } else if (contentType.startsWith('video/')) {
      return ArDriveIcons.fileVideo(
        size: size,
      );
    } else if (contentType.startsWith('audio/')) {
      return ArDriveIcons.fileMusic(
        size: size,
      );
    } else if (contentType.startsWith('text/') ||
        contentType == 'application/msword' ||
        contentType ==
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
      return ArDriveIcons.fileDoc(
        size: size,
      );
    } else if (contentType == 'application/json' ||
        contentType == 'application/xml' ||
        contentType == 'application/xhtml+xml') {
      return ArDriveIcons.fileCode(
        size: size,
      );
    } else {
      return ArDriveIcons.fileOutlined(
        size: size,
      );
    }
  }
}

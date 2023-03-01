import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class DriveExplorerItemTile extends TableRowWidget {
  DriveExplorerItemTile({
    required String name,
    required String size,
    required String lastUpdated,
    required Function() onPressed,
  }) : super(
          [
            GestureDetector(
              onTap: onPressed,
              child: Text(
                name,
                style: ArDriveTypography.body.buttonNormalBold(),
              ),
            ),
            Text(size, style: ArDriveTypography.body.xSmallRegular()),
            Text(lastUpdated, style: ArDriveTypography.body.captionRegular()),
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
      width: 40,
      height: 40,
      elevation: 0,
      contentPadding: EdgeInsets.zero,
      content: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: ArDriveImage(
              image: AssetImage(getAssetPath(item.contentType)),
              width: 20,
              height: 20,
            ),
          ),
          if (item.fileStatusFromTransactions != null)
            Positioned(
              right: 4,
              bottom: 4,
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

  // TODO: Move this to a helper class
  String getAssetPath(String contentType) {
    if (contentType == 'folder') {
      return Resources.images.fileTypes.folder;
    }
    if (contentType.startsWith('image/')) {
      return Resources.images.fileTypes.image;
    } else if (contentType.startsWith('video/')) {
      return Resources.images.fileTypes.video;
    } else if (contentType.startsWith('audio/')) {
      return Resources.images.fileTypes.music;
    } else if (contentType == 'application/msword' ||
        contentType ==
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
      return Resources.images.fileTypes.doc;
    } else if (contentType.startsWith('text/') ||
        contentType == 'application/json' ||
        contentType == 'application/xml' ||
        contentType == 'application/xhtml+xml') {
      return Resources.images.fileTypes.code;
    } else {
      return Resources.images.fileTypes.doc;
    }
  }
}

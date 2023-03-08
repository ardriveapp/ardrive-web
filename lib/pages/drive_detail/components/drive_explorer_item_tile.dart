import 'package:ardrive/components/components.dart';
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
    required String dateCreated,
    required Function() onPressed,
  }) : super(
          [
            GestureDetector(
              key: ValueKey(name),
              onTap: onPressed,
              child: Text(
                name,
                style: ArDriveTypography.body.buttonNormalBold(),
              ),
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
            child: ArDriveImage(
              image: AssetImage(getAssetPath(item.contentType)),
              width: 15,
              height: 15,
              fit: BoxFit.contain,
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

// build a DriveExplorerItemTileTrailing widget
class DriveExplorerItemTileTrailing extends StatefulWidget {
  const DriveExplorerItemTileTrailing({super.key, required this.item});

  final ArDriveDataTableItem item;

  @override
  State<DriveExplorerItemTileTrailing> createState() =>
      _DriveExplorerItemTileTrailingState();
}

class _DriveExplorerItemTileTrailingState
    extends State<DriveExplorerItemTileTrailing> {
  Alignment alignment = Alignment.topRight;

  @override
  void didChangeDependencies() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final renderBox = context.findRenderObject() as RenderBox?;

      final position = renderBox?.localToGlobal(Offset.zero);
      if (position != null) {
        final y = position.dy;

        final screenHeight = MediaQuery.of(context).size.height;

        if (y > screenHeight / 2) {
          alignment = Alignment.bottomRight;
        }
      }

      setState(() {});
    });

    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveDropdown(
      key: ValueKey(alignment),
      anchor: Aligned(
        follower: alignment,
        target: Alignment.topLeft,
      ),
      items: _getItems(widget.item, context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          ArDriveIcons.dots(),
        ],
      ),
    );
  }

  List<ArDriveDropdownItem> _getItems(
      ArDriveDataTableItem item, BuildContext context) {
    if (item is FolderDataTableItem) {
      return [
        ArDriveDropdownItem(
          onClick: () {
            promptToMove(
              context,
              driveId: item.driveId,
              selectedItems: [
                parseMoveItem(item),
              ],
            );
          },
          content: _buildItem('Move', ArDriveIcons.move()),
        ),
        ArDriveDropdownItem(
          onClick: () {
            promptToRenameModal(
              context,
              driveId: item.driveId,
              folderId: item.id,
              initialName: item.name,
            );
          },
          content: _buildItem('Rename', ArDriveIcons.edit()),
        ),
        ArDriveDropdownItem(
          onClick: () {
            _comingSoonModal();
          },
          content: _buildItem('More Info', ArDriveIcons.info()),
        ),
      ];
    }
    return [
      ArDriveDropdownItem(
        onClick: () {
          promptToDownloadProfileFile(
            context: context,
            file: item as FileDataTableItem,
          );
        },
        content: _buildItem('Download', ArDriveIcons.download()),
      ),
      ArDriveDropdownItem(
        onClick: () {
          promptToShareFile(
            context: context,
            driveId: item.driveId,
            fileId: item.id,
          );
        },
        content: _buildItem('Share File', ArDriveIcons.share()),
      ),
      ArDriveDropdownItem(
        onClick: () {
          _comingSoonModal();
        },
        content: _buildItem('Preview', ArDriveIcons.externalLink()),
      ),
      ArDriveDropdownItem(
        onClick: () {
          promptToRenameModal(
            context,
            driveId: item.driveId,
            fileId: item.id,
            initialName: item.name,
          );
        },
        content: _buildItem('Rename File', ArDriveIcons.edit()),
      ),
      ArDriveDropdownItem(
        onClick: () {
          promptToMove(
            context,
            driveId: item.driveId,
            selectedItems: [
              parseMoveItem(item),
            ],
          );
        },
        content: _buildItem('Move File', ArDriveIcons.move()),
      ),
      ArDriveDropdownItem(
        onClick: () {
          _comingSoonModal();
        },
        content: _buildItem('More Info', ArDriveIcons.info()),
      ),
    ];
  }

  _buildItem(String name, ArDriveIcon icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 41.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 375,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: ArDriveTypography.body.buttonNormalBold(),
            ),
            icon,
          ],
        ),
      ),
    );
  }

  void _comingSoonModal() {
    showAnimatedDialog(
      context,
      content: const ArDriveStandardModal(
        title: 'Not ready',
        description: 'Coming soon',
      ),
    );
  }
}

abstract class MoveItem {
  final String id;
  final String name;
  final String driveId;
  final String path;

  MoveItem({
    required this.id,
    required this.name,
    required this.driveId,
    required this.path,
  });
}

class MoveFolder extends MoveItem {
  MoveFolder({
    required String id,
    required String name,
    required String driveId,
    required String path,
  }) : super(
          id: id,
          name: name,
          driveId: driveId,
          path: path,
        );
}

class MoveFile extends MoveItem {
  MoveFile({
    required String id,
    required String name,
    required String driveId,
    required String path,
  }) : super(
          id: id,
          name: name,
          driveId: driveId,
          path: path,
        );
}

// parse ArDriveDataTableItem to MoveItem
MoveItem parseMoveItem(ArDriveDataTableItem item) {
  if (item is FolderDataTableItem) {
    return MoveFolder(
      id: item.id,
      name: item.name,
      driveId: item.driveId,
      path: item.path,
    );
  } else if (item is FileDataTableItem) {
    return MoveFile(
      id: item.id,
      name: item.name,
      driveId: item.driveId,
      path: item.path,
    );
  } else {
    throw Exception('Invalid ArDriveDataTableItem');
  }
}

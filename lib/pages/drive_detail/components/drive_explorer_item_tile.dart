import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/file_type_helper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DriveExplorerItemTile extends TableRowWidget {
  DriveExplorerItemTile({
    required String name,
    required String size,
    required String lastUpdated,
    required String dateCreated,
    required Function() onPressed,
  }) : super(
          [
            Text(name, style: ArDriveTypography.body.buttonNormalBold()),
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
    } else if (FileTypeHelper.isZip(contentType)) {
      return ArDriveIcons.fileZip(
        size: size,
      );
    } else if (FileTypeHelper.isImage(contentType)) {
      return ArDriveIcons.image(
        size: size,
      );
    } else if (FileTypeHelper.isVideo(contentType)) {
      return ArDriveIcons.fileVideo(
        size: size,
      );
    } else if (FileTypeHelper.isAudio(contentType)) {
      return ArDriveIcons.fileMusic(
        size: size,
      );
    } else if (FileTypeHelper.isDoc(contentType)) {
      return ArDriveIcons.fileDoc(
        size: size,
      );
    } else if (FileTypeHelper.isCode(contentType)) {
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

class DriveExplorerItemTileTrailing extends StatefulWidget {
  const DriveExplorerItemTileTrailing({
    super.key,
    required this.item,
    required this.drive,
  });

  final ArDriveDataTableItem item;
  final Drive drive;

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
    final isDriveOwner = widget.drive.ownerAddress ==
        context.read<ArDriveAuth>().currentUser?.walletAddress;
    if (item is FolderDataTableItem) {
      return [
        if (isDriveOwner) ...[
          ArDriveDropdownItem(
            onClick: () {
              promptToMove(
                context,
                driveId: item.driveId,
                selectedItems: [
                  item,
                ],
              );
            },
            content: _buildItem(
              appLocalizationsOf(context).move,
              ArDriveIcons.move(),
            ),
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
            content: _buildItem(
              appLocalizationsOf(context).rename,
              ArDriveIcons.edit(),
            ),
          ),
        ],
        ArDriveDropdownItem(
          onClick: () {
            _comingSoonModal();
          },
          content: _buildItem(
            appLocalizationsOf(context).moreInfo,
            ArDriveIcons.info(),
          ),
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
        content: _buildItem(
          appLocalizationsOf(context).download,
          ArDriveIcons.download(),
        ),
      ),
      ArDriveDropdownItem(
        onClick: () {
          promptToShareFile(
            context: context,
            driveId: item.driveId,
            fileId: item.id,
          );
        },
        content: _buildItem(
          appLocalizationsOf(context).shareFile,
          ArDriveIcons.share(),
        ),
      ),
      ArDriveDropdownItem(
        onClick: () {
          _comingSoonModal();
        },
        content: _buildItem(
          appLocalizationsOf(context).preview,
          ArDriveIcons.externalLink(),
        ),
      ),
      if (isDriveOwner) ...[
        ArDriveDropdownItem(
          onClick: () {
            promptToRenameModal(
              context,
              driveId: item.driveId,
              fileId: item.id,
              initialName: item.name,
            );
          },
          content: _buildItem(
            appLocalizationsOf(context).rename,
            ArDriveIcons.edit(),
          ),
        ),
        ArDriveDropdownItem(
          onClick: () {
            promptToMove(
              context,
              driveId: item.driveId,
              selectedItems: [item],
            );
          },
          content: _buildItem(
            appLocalizationsOf(context).move,
            ArDriveIcons.move(),
          ),
        ),
      ],
      ArDriveDropdownItem(
        onClick: () {
          _comingSoonModal();
        },
        content: _buildItem(
            appLocalizationsOf(context).moreInfo, ArDriveIcons.info()),
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

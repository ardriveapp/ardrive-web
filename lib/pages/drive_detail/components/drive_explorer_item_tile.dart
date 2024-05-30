import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/fs_entry_license_form.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/components/pin_indicator.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/file_type_helper.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DriveExplorerItemTile extends TableRowWidget {
  DriveExplorerItemTile({
    required String name,
    required String size,
    required String lastUpdated,
    required String dateCreated,
    required String license,
    required Function() onPressed,
    required bool isHidden,
  }) : super(
          [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                name,
                style: ArDriveTypography.body.buttonNormalBold().copyWith(
                      color: isHidden ? Colors.grey : null,
                    ),
                overflow: TextOverflow.fade,
                maxLines: 1,
                softWrap: false,
              ),
            ),
            Text(size, style: _driveExplorerItemTileTextStyle(isHidden)),
            Text(lastUpdated, style: _driveExplorerItemTileTextStyle(isHidden)),
            Text(dateCreated, style: _driveExplorerItemTileTextStyle(isHidden)),
            Text(license, style: ArDriveTypography.body.captionRegular()),
          ],
        );
}

TextStyle _driveExplorerItemTileTextStyle(bool isHidden) =>
    ArDriveTypography.body
        .captionRegular()
        .copyWith(color: isHidden ? Colors.grey : null);

class DriveExplorerItemTileLeading extends StatelessWidget {
  const DriveExplorerItemTileLeading({
    super.key,
    required this.item,
  });

  final ArDriveDataTableItem item;

  bool get isHidden => item.isHidden;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 0),
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
            child: getIconForContentType(
              item.contentType,
            ).copyWith(
              color: isHidden ? Colors.grey : null,
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
}

ArDriveIcon getIconForContentType(
  String contentType, {
  double size = 18,
  Color? color,
}) {
  contentType = contentType.toLowerCase();

  if (contentType == 'folder') {
    return ArDriveIcons.folderOutline(
      size: size,
      color: color,
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
  } else if (FileTypeHelper.isManifest(contentType)) {
    return ArDriveIcons.manifest(
      size: size,
    );
  } else {
    return ArDriveIcons.fileOutlined(
      size: size,
    );
  }
}

class DriveExplorerItemTileTrailing extends StatefulWidget {
  const DriveExplorerItemTileTrailing({
    super.key,
    required this.item,
    required this.drive,
    this.alignment = Alignment.topRight,
  });

  final ArDriveDataTableItem item;
  final Drive drive;
  final Alignment alignment;

  @override
  State<DriveExplorerItemTileTrailing> createState() =>
      _DriveExplorerItemTileTrailingState();
}

class _DriveExplorerItemTileTrailingState
    extends State<DriveExplorerItemTileTrailing> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (item is FolderDataTableItem &&
            item.isGhostFolder &&
            item.isOwner) ...[
          ArDriveButton(
            maxHeight: 36,
            style: ArDriveButtonStyle.primary,
            onPressed: () => showCongestionDependentModalDialog(
              context,
              () => promptToReCreateFolder(
                context,
                ghostFolder: item,
              ),
            ),
            fontStyle: ArDriveTypography.body.smallRegular(),
            text: appLocalizationsOf(context).fix,
          ),
          const SizedBox(
            width: 4,
          ),
        ],
        if (widget.item is FileDataTableItem &&
            (widget.item as FileDataTableItem).pinnedDataOwnerAddress !=
                null) ...{
          const PinIndicator(
            size: 32,
          ),
        },
        ArDriveDropdown(
          calculateVerticalAlignment: (isAboveHalfScreen) {
            if (isAboveHalfScreen) {
              return Alignment.bottomRight;
            } else {
              return Alignment.topRight;
            }
          },
          anchor: Aligned(
            follower: widget.alignment,
            target: Alignment.topLeft,
          ),
          items: _getItems(widget.item, context),
          child: HoverWidget(
            tooltip: appLocalizationsOf(context).showMenu,
            child: ArDriveIcons.kebabMenu(),
          ),
        ),
      ],
    );
  }

  List<ArDriveDropdownItem> _getItems(
    ArDriveDataTableItem item,
    BuildContext context,
  ) {
    final isOwner = item.isOwner;

    if (item is FolderDataTableItem) {
      return [
        ArDriveDropdownItem(
          onClick: () {
            final driveDetail = (context.read<DriveDetailCubit>().state
                as DriveDetailLoadSuccess);

            final zipName = item.id == driveDetail.currentDrive.rootFolderId
                ? driveDetail.currentDrive.name
                : item.name;

            promptToDownloadMultipleFiles(
              context,
              selectedItems: [item],
              zipName: zipName,
            );
          },
          content: _buildItem(
            appLocalizationsOf(context).download,
            ArDriveIcons.download2(
              size: defaultIconSize,
            ),
          ),
        ),
        if (isOwner) ...[
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
              ArDriveIcons.move(
                size: defaultIconSize,
              ),
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
              ArDriveIcons.editFilled(
                size: defaultIconSize,
              ),
            ),
          ),
          ArDriveDropdownItem(
            onClick: () {
              promptToLicense(
                context,
                driveId: item.driveId,
                selectedItems: [item],
              );
            },
            content: _buildItem(
              // TODO: Localize
              // appLocalizationsOf(context).license,
              'Add license',
              ArDriveIcons.license(
                size: defaultIconSize,
              ),
            ),
          ),
          hideFileDropdownItem(context, item),
        ],
        ArDriveDropdownItem(
          onClick: () {
            final bloc = context.read<DriveDetailCubit>();

            bloc.selectDataItem(item);
          },
          content: _buildItem(
            appLocalizationsOf(context).moreInfo,
            ArDriveIcons.info(
              size: defaultIconSize,
            ),
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
          ArDriveIcons.download2(
            size: defaultIconSize,
          ),
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
          ArDriveIcons.share(
            size: defaultIconSize,
          ),
        ),
      ),
      if (widget.drive.isPublic)
        ArDriveDropdownItem(
          onClick: () {
            final bloc = context.read<DriveDetailCubit>();

            bloc.launchPreview((item as FileDataTableItem).dataTxId);
          },
          content: _buildItem(
            appLocalizationsOf(context).preview,
            ArDriveIcons.eyeOpen(
              size: defaultIconSize,
            ),
          ),
        ),
      if (isOwner) ...[
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
            ArDriveIcons.editFilled(
              size: defaultIconSize,
            ),
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
            ArDriveIcons.move(
              size: defaultIconSize,
            ),
          ),
        ),
        if (item is FileDataTableItem && item.pinnedDataOwnerAddress == null)
          ArDriveDropdownItem(
            onClick: () {
              promptToLicense(
                context,
                driveId: item.driveId,
                selectedItems: [item],
              );
            },
            content: _buildItem(
              item.licenseTxId == null
                  ?
                  // TODO: Localize
                  // appLocalizationsOf(context).addLicense,
                  'Add license'
                  :
                  // TODO: Localize
                  // appLocalizationsOf(context).updateLicense,
                  'Update license',
              ArDriveIcons.license(
                size: defaultIconSize,
              ),
            ),
          ),
        hideFileDropdownItem(context, item),
      ],
      ArDriveDropdownItem(
        onClick: () {
          final bloc = context.read<DriveDetailCubit>();

          bloc.selectDataItem(item);
        },
        content: _buildItem(
          appLocalizationsOf(context).moreInfo,
          ArDriveIcons.info(
            size: defaultIconSize,
          ),
        ),
      ),
    ];
  }

  ArDriveDropdownItemTile _buildItem(String name, ArDriveIcon icon) {
    return ArDriveDropdownItemTile(name: name, icon: icon);
  }
}

// TODO: @thiagocarvalhodev remove this and use the AppPlatform class or change the name of the method
bool isMobile(BuildContext context) {
  final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
  return isPortrait;
}

class EntityActionsMenu extends StatelessWidget {
  const EntityActionsMenu({
    super.key,
    required this.item,
    this.withInfo = true,
    this.alignment = const Aligned(
      follower: Alignment.topRight,
      target: Alignment.topLeft,
    ),
    this.drive,
  });

  final ArDriveDataTableItem item;
  final bool withInfo;
  final Anchor alignment;
  final Drive? drive;

  @override
  Widget build(BuildContext context) {
    return ArDriveDropdown(
      height: isMobile(context) ? 44 : 60,
      anchor: alignment,
      items: _getItems(item, context, withInfo),
      child: HoverWidget(
        tooltip: appLocalizationsOf(context).showMenu,
        child: ArDriveIcons.dots(),
      ),
    );
  }

  List<ArDriveDropdownItem> _getItems(
      ArDriveDataTableItem item, BuildContext context, bool withInfo) {
    final isOwner = item.isOwner;

    if (item is FolderDataTableItem) {
      return [
        ArDriveDropdownItem(
          onClick: () {
            promptToDownloadMultipleFiles(
              context,
              selectedItems: [item],
              zipName: item.name,
            );
          },
          content: _buildItem(
            appLocalizationsOf(context).download,
            ArDriveIcons.download2(
              size: defaultIconSize,
            ),
          ),
        ),
        if (isOwner) ...[
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
              ArDriveIcons.move(
                size: defaultIconSize,
              ),
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
              ArDriveIcons.editFilled(
                size: defaultIconSize,
              ),
            ),
          ),
          hideFileDropdownItem(context, item),
        ],
        if (withInfo) _buildInfoOption(context),
      ];
    } else if (item is DriveDataItem) {
      return [
        ArDriveDropdownItem(
            onClick: () async {
              promptToDownloadMultipleFiles(context,
                  selectedItems: [item], zipName: item.name);
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).download,
              icon: ArDriveIcons.download2(
                size: defaultIconSize,
              ),
            )),
        ArDriveDropdownItem(
          onClick: () {
            promptToRenameDrive(
              context,
              driveId: drive!.id,
              driveName: drive!.name,
            );
          },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).renameDrive,
            icon: ArDriveIcons.edit(
              size: defaultIconSize,
            ),
          ),
        ),
        ArDriveDropdownItem(
          onClick: () {
            promptToShareDrive(
              context: context,
              drive: drive!,
            );
          },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).shareDrive,
            icon: ArDriveIcons.share(
              size: defaultIconSize,
            ),
          ),
        ),
        ArDriveDropdownItem(
          onClick: () {
            promptToExportCSVData(
              context: context,
              driveId: drive!.id,
            );
          },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).exportDriveContents,
            icon: ArDriveIcons.download2(
              size: defaultIconSize,
            ),
          ),
        ),
        ArDriveDropdownItem(
          onClick: () {
            final bloc = context.read<DriveDetailCubit>();

            bloc.selectDataItem(
              DriveDataTableItemMapper.fromDrive(
                drive!,
                (_) => null,
                0,
                isOwner,
              ),
            );
          },
          content: _buildItem(
            appLocalizationsOf(context).moreInfo,
            ArDriveIcons.info(
              size: defaultIconSize,
            ),
          ),
        )
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
          ArDriveIcons.download2(
            size: defaultIconSize,
          ),
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
          ArDriveIcons.share(
            size: defaultIconSize,
          ),
        ),
      ),
      ArDriveDropdownItem(
        onClick: () {
          final bloc = context.read<DriveDetailCubit>();

          bloc.launchPreview((item as FileDataTableItem).dataTxId);
        },
        content: _buildItem(
          appLocalizationsOf(context).preview,
          ArDriveIcons.newWindow(
            size: defaultIconSize,
          ),
        ),
      ),
      if (isOwner) ...[
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
            ArDriveIcons.editFilled(
              size: defaultIconSize,
            ),
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
            ArDriveIcons.move(
              size: defaultIconSize,
            ),
          ),
        ),
        hideFileDropdownItem(context, item),
      ],
      if (withInfo) _buildInfoOption(context)
    ];
  }

  _buildInfoOption(BuildContext context) {
    return ArDriveDropdownItem(
      onClick: () {
        final bloc = context.read<DriveDetailCubit>();

        bloc.selectDataItem(item);
      },
      content: _buildItem(
        appLocalizationsOf(context).moreInfo,
        ArDriveIcons.info(
          size: defaultIconSize,
        ),
      ),
    );
  }

  ArDriveDropdownItemTile _buildItem(String name, ArDriveIcon icon) {
    return ArDriveDropdownItemTile(name: name, icon: icon);
  }
}

ArDriveDropdownItem hideFileDropdownItem(
  BuildContext context,
  ArDriveDataTableItem item,
) {
  return ArDriveDropdownItem(
    onClick: () {
      promptToToggleHideState(
        context,
        item: item,
      );
    },
    content: ArDriveDropdownItemTile(
      name: item.isHidden
          ? appLocalizationsOf(context).unhide
          : appLocalizationsOf(context).hide,
      icon: item.isHidden
          ? ArDriveIcons.eyeOpen(size: defaultIconSize)
          : ArDriveIcons.eyeClosed(size: defaultIconSize),
    ),
  );
}

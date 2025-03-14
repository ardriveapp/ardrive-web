import 'package:ardrive/arns/presentation/ant_icon.dart';
import 'package:ardrive/arns/presentation/assign_name_modal.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/fs_entry_license_form.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/components/pin_indicator.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/drive_explorer/thumbnail/thumbnail_bloc.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DriveExplorerItemTile extends TableRowWidget {
  DriveExplorerItemTile({
    required String name,
    required String size,
    required DateTime lastUpdated,
    required DateTime dateCreated,
    required String license,
    required Function() onPressed,
    required bool isHidden,
    required ArdriveTypographyNew typography,
    required ArDriveDataTableItem dataTableItem,
    required ArDriveColorTokens colorTokens,
  }) : super(
          [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: typography.paragraphNormal(
                        color: isHidden ? Colors.grey : null,
                        fontWeight: ArFontWeight.semiBold,
                      ),
                      overflow: TextOverflow.fade,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  if (dataTableItem is FileDataTableItem &&
                      dataTableItem.assignedNames != null &&
                      dataTableItem.assignedNames!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Transform(
                        transform: Matrix4.translationValues(0, 2, 0),
                        child: AntIcon(fileDataTableItem: dataTableItem)),
                  ]
                ],
              ),
            ),
            Text(size,
                style: _driveExplorerItemTileTextStyle(
                    isHidden, typography, colorTokens)),
            ArDriveTooltip(
              message: formatDateToUtcString(lastUpdated),
              child: Text(yMMdDateFormatter.format(lastUpdated),
                  style: _driveExplorerItemTileTextStyle(
                      isHidden, typography, colorTokens)),
            ),
            ArDriveTooltip(
              message: formatDateToUtcString(dateCreated),
              child: Text(yMMdDateFormatter.format(dateCreated),
                  style: _driveExplorerItemTileTextStyle(
                      isHidden, typography, colorTokens)),
            ),
            Text(license, style: ArDriveTypography.body.captionRegular()),
          ],
        );
}

TextStyle _driveExplorerItemTileTextStyle(bool isHidden,
        ArdriveTypographyNew typography, ArDriveColorTokens colorTokens) =>
    typography.paragraphNormal(
      color: isHidden ? Colors.grey : null,
      fontWeight: ArFontWeight.semiBold,
    );

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
    if (item is FileDataTableItem && FileTypeHelper.isImage(item.contentType)) {
      final file = item as FileDataTableItem;

      return ArDriveCard(
        width: 30,
        height: 30,
        elevation: 0,
        contentPadding: EdgeInsets.zero,
        content: Stack(
          children: [
            BlocProvider(
              create: (context) => ThumbnailBloc(
                  thumbnailRepository: context.read<ThumbnailRepository>())
                ..add(
                  GetThumbnail(fileDataTableItem: file),
                ),
              child: BlocBuilder<ThumbnailBloc, ThumbnailState>(
                builder: (context, state) {
                  if (state is ThumbnailLoading) {
                    return const SizedBox();
                  }

                  if (state is ThumbnailLoaded) {
                    if (state.thumbnail.url != null) {
                      return Align(
                        alignment: Alignment.center,
                        child: Image.network(
                          state.thumbnail.url!,
                          width: 30,
                          height: 30,
                          filterQuality: FilterQuality.high,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return getIconForContentType(
                              item.contentType,
                            ).copyWith(
                              color: isHidden ? Colors.grey : null,
                            );
                          },
                        ),
                      );
                    }

                    return Align(
                      alignment: Alignment.center,
                      child: Image.memory(
                        state.thumbnail.data!,
                        width: 30,
                        height: 30,
                        filterQuality: FilterQuality.low,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          logger.d('Error loading thumbnail: $error');
                          return getIconForContentType(
                            item.contentType,
                          ).copyWith(
                            color: isHidden ? Colors.grey : null,
                          );
                        },
                      ),
                    );
                  }

                  return Align(
                    alignment: Alignment.center,
                    child: getIconForContentType(
                      item.contentType,
                    ).copyWith(
                      color: isHidden ? Colors.grey : null,
                    ),
                  );
                },
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

    return ArDriveCard(
      width: 30,
      height: 30,
      elevation: 0,
      contentPadding: EdgeInsets.zero,
      content: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {
                context
                    .read<ThumbnailRepository>()
                    .uploadThumbnail(fileId: item.id);
              },
              child: getIconForContentType(
                item.contentType,
              ).copyWith(
                color: isHidden ? Colors.grey : null,
              ),
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
  } else if (contentType == 'drive') {
    return ArDriveIcons.publicDrive(
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
    final double height = isMobile(context) ? 44 : 48;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

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
          height: height,
          anchor: Aligned(
            follower: widget.alignment,
            target: Alignment.topLeft,
          ),
          items: _getItems(widget.item, context, height),
          child: HoverWidget(
            tooltip: appLocalizationsOf(context).showMenu,
            child: ArDriveIcons.kebabMenu(
              color: colorTokens.iconMid,
            ),
          ),
        ),
      ],
    );
  }

  List<ArDriveDropdownItem> _getItems(
    ArDriveDataTableItem item,
    BuildContext context,
    double height,
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
            ArDriveIcons.download(
              size: defaultIconSize,
            ),
            height: height,
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
              height: height,
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
              height: height,
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
              height: height,
            ),
          ),
          if (isOwner) hideFileDropdownItem(context, item),
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
            height: height,
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
          ArDriveIcons.download(
            size: defaultIconSize,
          ),
          height: height,
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
          height: height,
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
            ArDriveIcons.newWindow(
              size: defaultIconSize,
            ),
            height: height,
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
            height: height,
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
            height: height,
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
              height: height,
            ),
          ),
        if (widget.drive.isPublic && AppPlatform.isWeb())
          ArDriveDropdownItem(
            onClick: () {
              showAssignArNSNameModal(
                context,
                file: item as FileDataTableItem,
                driveDetailCubit: context.read<DriveDetailCubit>(),
              );
            },
            content: _buildItem(
              'Assign ArNS name',
              ArDriveIcons.addArnsName(
                size: defaultIconSize,
              ),
              height: height,
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
          height: height,
        ),
      ),
    ];
  }

  ArDriveDropdownItemTile _buildItem(
    String name,
    ArDriveIcon icon, {
    double? height,
  }) {
    return ArDriveDropdownItemTile(name: name, icon: icon, height: height);
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
    this.isFileRevision = false,
  });

  final ArDriveDataTableItem item;
  final bool withInfo;
  final Anchor alignment;
  final Drive? drive;
  final bool isFileRevision;

  @override
  Widget build(BuildContext context) {
    final items = _getItems(item, context, withInfo, isFileRevision);
    final double height = isMobile(context) ? 44 : 48;
    return ArDriveDropdown(
      height: height,
      maxHeight: items.length * height,
      anchor: alignment,
      items: items,
      hasBorder: false,
      hasDivider: false,
      child: HoverWidget(
        tooltip: appLocalizationsOf(context).showMenu,
        child: ArDriveIcons.dots(),
      ),
    );
  }

  List<ArDriveDropdownItem> _getItems(ArDriveDataTableItem item,
      BuildContext context, bool withInfo, bool isFileRevision) {
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
            ArDriveIcons.download(
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
              icon: ArDriveIcons.download(
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
        if (isOwner)
          ArDriveDropdownItem(
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
            icon: ArDriveIcons.download(
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
          ArDriveIcons.download(
            size: defaultIconSize,
          ),
        ),
      ),
      if (!isFileRevision) ...[
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
      ],
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
      if (isOwner && !isFileRevision) ...[
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
      if (withInfo) _buildInfoOption(context),
      if (isFileRevision) ...[
        ArDriveDropdownItem(
          onClick: () {
            Clipboard.setData(
                ClipboardData(text: (item as FileDataTableItem).dataTxId));
          },
          content: _buildItem(
            appLocalizationsOf(context).copyDataTxID,
            ArDriveIcons.copy(
              size: defaultIconSize,
            ),
          ),
        ),
        if (item is FileDataTableItem && item.metadataTx != null)
          ArDriveDropdownItem(
            onClick: () {
              Clipboard.setData(ClipboardData(text: (item).metadataTx!.id));
            },
            content: _buildItem(
              appLocalizationsOf(context).copyMetadataTxID,
              ArDriveIcons.copy(
                size: defaultIconSize,
              ),
            ),
          ),
      ],
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

  ArDriveDropdownItemTile _buildItem(
    String name,
    ArDriveIcon icon, {
    double? height,
  }) {
    return ArDriveDropdownItemTile(name: name, icon: icon, height: height);
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

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
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
            Text(size,
                style: ArDriveTypography.body.captionRegular().copyWith(
                      color: isHidden ? Colors.grey : null,
                    )),
            Text(lastUpdated,
                style: ArDriveTypography.body.captionRegular().copyWith(
                      color: isHidden ? Colors.grey : null,
                    )),
            Text(dateCreated,
                style: ArDriveTypography.body.captionRegular().copyWith(
                      color: isHidden ? Colors.grey : null,
                    )),
          ],
        );
}

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

ArDriveIcon getIconForContentType(String contentType, {double size = 18}) {
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
          // ignore: sized_box_for_whitespace
          child: HoverWidget(
            tooltip: appLocalizationsOf(context).showMenu,
            child: ArDriveIcons.kebabMenu(),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingDialog(BuildContext context) {
    return const ArDriveStandardModal(
      title: 'Loading',
      description: 'Hello!',
      content: Column(
        children: [
          Center(
            child: CircularProgressIndicator(),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmHideDialog(
    BuildContext context,
    ConfirmingHideState state,
  ) {
    return ArDriveStandardModal(
      title: 'Confirm Hide',
      description: 'Hello!',
      content: Column(
        children: [
          PaymentMethodSelector(
            uploadMethod: state.uploadMethod,
            costEstimateAr: state.costEstimateAr,
            costEstimateTurbo: state.costEstimateTurbo,
            hasNoTurboBalance: state.hasNoTurboBalance,
            isTurboUploadPossible: state.isTurboUploadPossible,
            arBalance: state.arBalance,
            sufficientArBalance: state.sufficientArBalance,
            turboCredits: state.turboCredits,
            sufficentCreditsBalance: state.sufficentCreditsBalance,
            isFreeThanksToTurbo: state.isFreeThanksToTurbo,
            onArSelect: () {
              context.read<HideBloc>().add(
                    const SelectUploadMethodEvent(
                      uploadMethod: UploadMethod.ar,
                    ),
                  );
            },
            onTurboSelect: () {
              context.read<HideBloc>().add(
                    const SelectUploadMethodEvent(
                      uploadMethod: UploadMethod.turbo,
                    ),
                  );
            },
            onTurboTopupSucess: () {
              context.read<HideBloc>().add(
                    const RefreshTurboBalanceEvent(),
                  );
            },
          )
        ],
      ),
      actions: [
        ModalAction(
          action: () {
            Navigator.of(context).pop();
          },
          title: 'Cancel',
        ),
        ModalAction(
          action: () {
            context.read<HideBloc>().add(const ConfirmUploadEvent());
            Navigator.of(context).pop();
          },
          title: 'Confirm',
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
              final hideBloc = context.read<HideBloc>();

              if (item.isHidden) {
                hideBloc.add(UnhideFolderEvent(
                  driveId: widget.drive.id,
                  folderId: item.id,
                ));
                promptToHide(context);
              } else {
                hideBloc.add(HideFolderEvent(
                  driveId: widget.drive.id,
                  folderId: item.id,
                ));
                promptToHide(context);
              }
            },
            content: _buildItem(
              item.isHidden ? 'Unhide this folder' : 'Hide this folder',
              ArDriveIcons.x(
                size: defaultIconSize,
              ),
            ),
          ),
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
        ArDriveDropdownItem(
          onClick: () {
            final hideBloc = context.read<HideBloc>();

            if (item.isHidden) {
              hideBloc.add(UnhideFileEvent(
                driveId: widget.drive.id,
                fileId: item.id,
              ));
              promptToHide(context);
            } else {
              hideBloc.add(HideFileEvent(
                driveId: widget.drive.id,
                fileId: item.id,
              ));
              promptToHide(context);
            }
          },
          content: _buildItem(
            item.isHidden ? 'Unhide this file' : 'Hide this file',
            ArDriveIcons.x(
              size: defaultIconSize,
            ),
          ),
        ),
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
      // ignore: sized_box_for_whitespace
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

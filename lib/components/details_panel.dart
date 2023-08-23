import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/dotted_line.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/pin_indicator.dart';
import 'package:ardrive/components/sizes.dart';
import 'package:ardrive/components/truncated_address.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../blocs/blocs.dart';

class DetailsPanel extends StatefulWidget {
  const DetailsPanel({
    super.key,
    required this.item,
    required this.maybeSelectedItem,
    required this.drivePrivacy,
    this.revisions,
    this.fileKey,
    required this.isSharePage,
    this.currentDrive,
  });

  final ArDriveDataTableItem item;
  final SelectedItem? maybeSelectedItem;
  final Privacy drivePrivacy;
  final List<FileRevision>? revisions;
  final SecretKey? fileKey;
  final bool isSharePage;
  final Drive? currentDrive;

  @override
  State<DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<DetailsPanel> {
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      // Specify a key to ensure a new cubit is provided when the folder/file id changes.
      key: ValueKey(
        '${widget.item.driveId}${widget.item.id}${widget.item.name}',
      ),
      providers: [
        BlocProvider<FsEntryInfoCubit>(
          create: (context) => FsEntryInfoCubit(
            driveId: widget.item.driveId,
            maybeSelectedItem: widget.item,
            driveDao: context.read<DriveDao>(),
          ),
        ),
        BlocProvider<FsEntryPreviewCubit>(
          create: (context) => FsEntryPreviewCubit(
            crypto: ArDriveCrypto(),
            isSharedFile: widget.isSharePage,
            driveId: widget.item.driveId,
            fileKey: widget.fileKey,
            maybeSelectedItem: widget.item,
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            arweave: context.read<ArweaveService>(),
            configService: context.read<ConfigService>(),
          ),
        )
      ],
      child: BlocBuilder<FsEntryPreviewCubit, FsEntryPreviewState>(
          builder: (context, previewState) {
        return BlocBuilder<FsEntryInfoCubit, FsEntryInfoState>(
          builder: (context, state) {
            final tabs = [
              if (previewState is FsEntryPreviewSuccess)
                ArDriveTab(
                    Tab(
                      child: Text(
                        appLocalizationsOf(context).itemPreviewEmphasized,
                      ),
                    ),
                    _buildPreview(previewState)),
              ArDriveTab(
                Tab(
                  child: Text(
                    appLocalizationsOf(context).itemDetailsEmphasized,
                  ),
                ),
                _buildDetails(state),
              ),
              ArDriveTab(
                Tab(
                  child: Text(
                    appLocalizationsOf(context).itemActivityEmphasized,
                  ),
                ),
                BlocProvider(
                  create: (context) => FsEntryActivityCubit(
                    driveId: widget.item.driveId,
                    maybeSelectedItem: widget.item,
                    driveDao: context.read<DriveDao>(),
                  ),
                  child:
                      BlocBuilder<FsEntryActivityCubit, FsEntryActivityState>(
                    builder: (context, state) {
                      return _buildActivity(state);
                    },
                  ),
                ),
              )
            ];
            return SizedBox(
              child: ArDriveCard(
                borderRadius: AppPlatform.isMobile || AppPlatform.isMobileWeb()
                    ? 0
                    : null,
                backgroundColor: ArDriveTheme.of(context)
                    .themeData
                    .tableTheme
                    .backgroundColor,
                contentPadding: const EdgeInsets.all(24),
                content: Column(
                  children: [
                    if (!widget.isSharePage)
                      ScreenTypeLayout.builder(
                        desktop: (context) => Column(
                          children: [
                            DetailsPanelToolbar(
                              item: widget.item,
                            ),
                            const SizedBox(
                              height: 24,
                            ),
                          ],
                        ),
                        mobile: (context) => const SizedBox.shrink(),
                      ),
                    ArDriveCard(
                      contentPadding: const EdgeInsets.all(24),
                      backgroundColor: ArDriveTheme.of(context)
                          .themeData
                          .tableTheme
                          .selectedItemColor,
                      content: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          DriveExplorerItemTileLeading(
                            item: widget.item,
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          Expanded(
                            child: Text(
                              widget.item.name,
                              style: ArDriveTypography.body.buttonLargeBold(),
                            ),
                          ),
                          if (widget.item is FileDataTableItem &&
                              (widget.item as FileDataTableItem)
                                      .pinnedDataOwnerAddress !=
                                  null) ...{
                            const PinIndicator(
                              size: 32,
                            ),
                          },
                          if (widget.currentDrive != null &&
                              !widget.isSharePage)
                            ScreenTypeLayout.builder(
                              desktop: (context) => const SizedBox.shrink(),
                              mobile: (context) => EntityActionsMenu(
                                drive: widget.currentDrive,
                                withInfo: false,
                                item: widget.item,
                                alignment: const Aligned(
                                  follower: Alignment.topRight,
                                  target: Alignment.bottomRight,
                                  offset: Offset(24, 32),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      height: 24,
                    ),
                    Expanded(
                      child: ArDriveTabView(
                        key: Key(widget.item.id + tabs.length.toString()),
                        tabs: tabs,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildPreview(previewState) {
    return Align(
      alignment: Alignment.center,
      child: FsEntryPreviewWidget(
        key: ValueKey(widget.item.id),
        state: previewState,
      ),
    );
  }

  Widget _buildDetails(FsEntryInfoState state) {
    late List<Widget> children;
    if (state is FsEntryInfoSuccess<FolderNode>) {
      children = _folderDetails(state);
    } else if (state is FsEntryInfoSuccess<FileEntry> ||
        widget.revisions != null) {
      children = _fileDetails(state as FsEntryInfoSuccess);
    } else if (state is FsEntryInfoSuccess<Drive>) {
      children = _driveDetails(state);
    } else {
      children = [
        const Center(
          child: CircularProgressIndicator(),
        )
      ];
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      children: children,
    );
  }

  List<Widget> _folderDetails(
    FsEntryInfoSuccess<FolderNode> folder,
  ) {
    // itemContains
    return [
      DetailsPanelItem(
        leading: CopyButton(text: folder.entry.folder.id),
        itemTitle: appLocalizationsOf(context).folderID,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          fileAndFolderCountsToString(
            folderCount: folder.entry.getRecursiveSubFolderCount(),
            fileCount: folder.entry.getRecursiveFileCount(),
            localizations: appLocalizationsOf(context),
          ),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).itemContains,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.lastUpdated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.dateCreated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: CopyButton(
          text: folder.entry.folder.driveId,
        ),
        itemTitle: appLocalizationsOf(context).driveID,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArDriveIconButton(
              tooltip: appLocalizationsOf(context).viewOnViewBlock,
              icon: ArDriveIcons.newWindow(size: 20),
              onPressed: () {
                openUrl(
                  url: 'https://viewblock.io/arweave/tx/${folder.metadataTxId}',
                );
              },
            ),
            const SizedBox(width: 12),
            CopyButton(
              text: folder.metadataTxId,
            ),
          ],
        ),
        itemTitle: appLocalizationsOf(context).metadataTxID,
      ),
    ];
  }

  List<Widget> _driveDetails(FsEntryInfoSuccess state) {
    return [
      DetailsPanelItem(
        leading: CopyButton(text: widget.item.id),
        itemTitle: appLocalizationsOf(context).driveID,
      ),
      sizedBoxHeight16px,
      // size
      DetailsPanelItem(
        leading: Text(
          filesize((state as FsEntryDriveInfoSuccess)
              .rootFolderTree
              .computeFolderSize()),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).size,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          fileAndFolderCountsToString(
            fileCount: state.rootFolderTree.getRecursiveFileCount(),
            folderCount: state.rootFolderTree.getRecursiveSubFolderCount(),
            localizations: appLocalizationsOf(context),
          ),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).itemContains,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.lastUpdated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.dateCreated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArDriveIconButton(
              tooltip: appLocalizationsOf(context).viewOnViewBlock,
              icon: ArDriveIcons.newWindow(size: 20),
              onPressed: () {
                openUrl(
                  url: 'https://viewblock.io/arweave/tx/${state.metadataTxId}',
                );
              },
            ),
            const SizedBox(width: 12),
            CopyButton(
              text: state.metadataTxId,
            ),
          ],
        ),
        itemTitle: appLocalizationsOf(context).metadataTxID,
      ),
    ];
  }

  List<Widget> _fileDetails(FsEntryInfoSuccess state) {
    String? pinnedDataOwnerAddress =
        (widget.item as FileDataTableItem).pinnedDataOwnerAddress;

    return [
      DetailsPanelItem(
        leading: CopyButton(text: widget.item.id),
        itemTitle: appLocalizationsOf(context).fileID,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          filesize(widget.item.size),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).size,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.lastUpdated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.dateCreated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          widget.item.contentType,
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).fileType,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArDriveIconButton(
              tooltip: appLocalizationsOf(context).viewOnViewBlock,
              icon: ArDriveIcons.newWindow(size: 20),
              onPressed: () {
                openUrl(
                  url: 'https://viewblock.io/arweave/tx/${state.metadataTxId}',
                );
              },
            ),
            const SizedBox(width: 12),
            CopyButton(
              text: state.metadataTxId,
            ),
          ],
        ),
        itemTitle: appLocalizationsOf(context).metadataTxID,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArDriveIconButton(
              tooltip: appLocalizationsOf(context).viewOnViewBlock,
              icon: ArDriveIcons.newWindow(size: 20),
              onPressed: () {
                openUrl(
                  url:
                      'https://viewblock.io/arweave/tx/${(widget.item as FileDataTableItem).dataTxId}',
                );
              },
            ),
            const SizedBox(width: 12),
            CopyButton(
              text: (widget.item as FileDataTableItem).dataTxId,
            ),
          ],
        ),
        itemTitle: appLocalizationsOf(context).dataTxID,
      ),
      if (pinnedDataOwnerAddress != null) ...[
        sizedBoxHeight16px,
        DetailsPanelItem(
          leading: TruncatedAddress(walletAddress: pinnedDataOwnerAddress),
          itemTitle: appLocalizationsOf(context).uploadedBy,
        ),
      ]
    ];
  }

  Widget _buildActivity(FsEntryActivityState state) {
    if (widget.revisions != null) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        itemCount: widget.revisions!.length,
        itemBuilder: (context, inded) {
          final revision = widget.revisions![inded];
          final file = ARFSFactory().getARFSFileFromFileRevision(revision);

          return _buildFileActivity(
            file,
            revision.action,
            widget.fileKey,
          );
        },
        separatorBuilder: (contexr, index) => const SizedBox(
          height: 16,
        ),
      );
    }

    if (state is FsEntryActivitySuccess) {
      if (state.revisions.isNotEmpty) {
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          separatorBuilder: (context, index) => sizedBoxHeight16px,
          itemCount: state.revisions.length,
          itemBuilder: (context, index) {
            final revision = state.revisions[index];
            String title = '';
            String subtitle = '';

            if (revision is FolderRevisionWithTransaction) {
              switch (revision.action) {
                case RevisionAction.create:
                  title = appLocalizationsOf(context)
                      .folderWasCreatedWithName(revision.name);
                  break;
                case RevisionAction.rename:
                  title = appLocalizationsOf(context)
                      .folderWasRenamed(revision.name);
                  break;
                case RevisionAction.move:
                  title = appLocalizationsOf(context).folderWasMoved;
                  break;
                default:
                  title = appLocalizationsOf(context).folderWasModified;
              }
              subtitle = yMMdDateFormatter.format(revision.dateCreated);

              return DetailsPanelItem(
                itemSubtitle: subtitle,
                itemTitle: title,
              );
            } else if (revision is FileRevisionWithTransactions) {
              final file = ARFSFactory()
                  .getARFSFileFromFileRevisionWithTransactions(revision);

              return _buildFileActivity(file, revision.action, null);
            } else if (revision is DriveRevisionWithTransaction) {
              switch (revision.action) {
                case RevisionAction.create:
                  title = appLocalizationsOf(context)
                      .driveWasCreatedWithName(revision.name);
                  break;
                case RevisionAction.rename:
                  title = appLocalizationsOf(context)
                      .driveWasRenamed(revision.name);
                  break;
                default:
                  title = appLocalizationsOf(context).driveWasModified;
              }

              subtitle = yMMdDateFormatter.format(revision.dateCreated);

              return DetailsPanelItem(
                itemSubtitle: subtitle,
                itemTitle: title,
              );
            }

            return const SizedBox();
          },
        );
      }
    }
    return const Center(child: Text('Loading...'));
  }

  Widget _buildFileActivity(
    ARFSFileEntity file,
    String action,
    SecretKey? key,
  ) {
    late String title;
    String? subtitle;
    Widget? leading;

    switch (action) {
      case RevisionAction.create:
        if (file.pinnedDataOwnerAddress != null) {
          title = appLocalizationsOf(context).fileWasPinnedToTheDrive;
        } else {
          title = appLocalizationsOf(context).fileWasCreatedWithName(file.name);
        }
        leading = _DownloadOrPreview(
          isSharedFile: widget.isSharePage,
          privacy: widget.drivePrivacy,
          fileRevision: file,
          fileKey: key,
        );
        break;
      case RevisionAction.rename:
        title = appLocalizationsOf(context).fileWasRenamed(file.name);
        break;
      case RevisionAction.move:
        title = appLocalizationsOf(context).fileWasMoved;
        break;
      case RevisionAction.uploadNewVersion:
        title = appLocalizationsOf(context).fileHadANewRevision;
        leading = leading = _DownloadOrPreview(
          isSharedFile: widget.isSharePage,
          privacy: widget.drivePrivacy,
          fileRevision: file,
          fileKey: key,
        );
        break;
      default:
        title = appLocalizationsOf(context).fileWasModified;
    }
    subtitle = yMMdDateFormatter.format(file.unixTime);

    return DetailsPanelItem(
      leading: leading ?? const SizedBox(),
      itemTitle: title,
      itemSubtitle: subtitle,
    );
  }
}

class EntityRevision {
  final String name;
  final DateTime dateCreated;
  final String action;

  EntityRevision({
    required this.name,
    required this.dateCreated,
    required this.action,
  });
}

class DetailsPanelItem extends StatelessWidget {
  const DetailsPanelItem({
    super.key,
    required this.itemTitle,
    this.itemSubtitle,
    this.leading,
  });

  final String itemTitle;
  final String? itemSubtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        itemTitle,
                        style: ArDriveTypography.body.buttonNormalRegular(),
                        maxLines: 2,
                      ),
                    ),
                    if (itemSubtitle != null)
                      Text(
                        itemSubtitle!,
                        style: ArDriveTypography.body.xSmallRegular(),
                      ),
                  ],
                ),
              ),
              if (leading != null) leading!,
            ],
          ),
        ),
        const SizedBox(
          height: 18,
        ),
        HorizontalDottedLine(
          color: ArDriveTheme.of(context).themeData.colors.themeBorderDefault,
          width: double.maxFinite,
        ),
      ],
    );
  }
}

class CopyButton extends StatefulWidget {
  final String text;
  final double size;
  final bool showCopyText;
  final Widget? child;
  final int positionY;
  final int positionX;
  final Color? copyMessageColor;

  const CopyButton({
    Key? key,
    required this.text,
    this.size = 20,
    this.showCopyText = true,
    this.child,
    this.positionY = 40,
    this.positionX = 20,
    this.copyMessageColor,
  }) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _CopyButtonState createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _showCheck = false;
  OverlayEntry? _overlayEntry;

  @override
  dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child != null) {
      return GestureDetector(
        onTap: _copy,
        child: HoverWidget(
          hoverScale: 1,
          child: widget.child!,
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: ArDriveIconButton(
        tooltip: _showCheck ? '' : appLocalizationsOf(context).copyTooltip,
        onPressed: _copy,
        icon: _showCheck
            ? ArDriveIcons.checkCirle(
                size: widget.size,
                color: ArDriveTheme.of(context)
                    .themeData
                    .colors
                    .themeSuccessDefault,
              )
            : ArDriveIcons.copy(size: widget.size),
      ),
    );
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    if (mounted) {
      if (_showCheck) {
        return;
      }

      setState(() {
        _showCheck = true;
        if (widget.showCopyText) {
          _overlayEntry = _createOverlayEntry(context);
          Overlay.of(context).insert(_overlayEntry!);
        }

        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) {
            return;
          }

          setState(() {
            _showCheck = false;
            if (_overlayEntry != null && _overlayEntry!.mounted) {
              _overlayEntry?.remove();
            }
          });
        });
      });
    }
  }

  OverlayEntry _createOverlayEntry(BuildContext parentContext) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset buttonPosition = button.localToGlobal(Offset.zero);

    return OverlayEntry(
      builder: (context) => Positioned(
        left: buttonPosition.dx - widget.positionX,
        top: buttonPosition.dy - widget.positionY,
        child: Material(
          color: widget.copyMessageColor ??
              ArDriveTheme.of(context).themeData.backgroundColor,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Center(
              child: Text(
                'Copied!',
                style: ArDriveTypography.body.smallRegular(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadOrPreview extends StatelessWidget {
  const _DownloadOrPreview({
    Key? key,
    required this.privacy,
    required this.fileRevision,
    this.fileKey,
    this.isSharedFile = false,
  }) : super(key: key);

  final String privacy;
  final ARFSFileEntity fileRevision;
  final SecretKey? fileKey;
  final bool isSharedFile;

  @override
  Widget build(BuildContext context) {
    return ArDriveIconButton(
      onPressed: () {
        return downloadOrPreviewRevision(
          drivePrivacy: privacy,
          context: context,
          revision: fileRevision,
          fileKey: fileKey,
          isSharedFile: isSharedFile,
        );
      },
      tooltip: appLocalizationsOf(context).download,
      icon: ArDriveIcons.download(size: 20),
    );
  }
}

void downloadOrPreviewRevision({
  required String drivePrivacy,
  required BuildContext context,
  required ARFSFileEntity revision,
  SecretKey? fileKey,
  bool isSharedFile = false,
}) {
  if (isSharedFile) {
    promptToDownloadSharedFile(
      context: context,
      revision: revision,
      fileKey: fileKey,
    );

    return;
  }

  promptToDownloadFileRevision(context: context, revision: revision);
}

class DetailsPanelToolbar extends StatelessWidget {
  const DetailsPanelToolbar({
    super.key,
    required this.item,
  });

  final ArDriveDataTableItem item;

  @override
  Widget build(BuildContext context) {
    final drive =
        (context.read<DriveDetailCubit>().state as DriveDetailLoadSuccess)
            .currentDrive;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: ArDriveTheme.of(context)
              .themeData
              .colors
              .themeBorderDefault
              .withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const SizedBox(
            width: 16,
          ),
          if (item is FileDataTableItem || item is DriveDataItem)
            _buildActionIcon(
              tooltip: _getShareTooltip(item, context),
              icon: ArDriveIcons.share(size: defaultIconSize),
              onTap: () {
                if (item is FileDataTableItem) {
                  promptToShareFile(
                    context: context,
                    driveId: item.driveId,
                    fileId: item.id,
                  );
                } else if (item is DriveDataItem) {
                  promptToShareDrive(
                    context: context,
                    drive: drive,
                  );
                }
              },
            ),
          if (item is FileDataTableItem) ...[
            _buildActionIcon(
              tooltip: appLocalizationsOf(context).download,
              icon: ArDriveIcons.download(size: defaultIconSize),
              onTap: () {
                promptToDownloadProfileFile(
                  context: context,
                  file: item as FileDataTableItem,
                );
              },
            ),
            if (drive.isPublic)
              _buildActionIcon(
                tooltip: appLocalizationsOf(context).preview,
                icon: ArDriveIcons.newWindow(size: defaultIconSize),
                onTap: () {
                  final bloc = context.read<DriveDetailCubit>();
                  bloc.launchPreview((item as FileDataTableItem).dataTxId);
                },
              ),
          ],
          if (isDriveOwner(context.read<ArDriveAuth>(), drive.ownerAddress))
            _buildActionIcon(
              tooltip: appLocalizationsOf(context).rename,
              icon: ArDriveIcons.edit(size: defaultIconSize),
              onTap: () {
                if (item is DriveDataItem) {
                  promptToRenameDrive(
                    context,
                    driveId: drive.id,
                    driveName: drive.name,
                  );
                  return;
                }

                promptToRenameModal(
                  context,
                  driveId: drive.id,
                  initialName: item.name,
                  fileId: item is FileDataTableItem ? item.id : null,
                  folderId: item is FolderDataTableItem ? item.id : null,
                );
              },
            ),
          if (item.isOwner &&
              (item is FileDataTableItem || item is FolderDataTableItem))
            _buildActionIcon(
              tooltip: appLocalizationsOf(context).move,
              icon: ArDriveIcons.move(size: defaultIconSize),
              onTap: () {
                promptToMove(context, driveId: drive.id, selectedItems: [item]);
              },
            ),
          const Spacer(),
          _buildActionIcon(
            tooltip: appLocalizationsOf(context).close,
            icon: ArDriveIcons.x(size: defaultIconSize),
            onTap: () {
              final bloc = context.read<DriveDetailCubit>();
              bloc.toggleSelectedItemDetails();
            },
          ),
        ],
      ),
    );
  }

  String _getShareTooltip(ArDriveDataTableItem item, BuildContext context) {
    if (item is FileDataTableItem) {
      return appLocalizationsOf(context).shareFile;
    } else if (item is DriveDataItem) {
      return appLocalizationsOf(context).shareDrive;
    } else {
      return '';
    }
  }

  Widget _buildActionIcon({
    required ArDriveIcon icon,
    required VoidCallback onTap,
    String? tooltip,
    double padding = 8,
  }) {
    return Padding(
      padding: EdgeInsets.only(right: padding),
      child: ArDriveIconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: icon,
      ),
    );
  }
}

import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/dotted_line.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/blocs.dart';
import '../services/arweave/arweave_service.dart';
import 'file_download_dialog.dart';

class DetailsPanel extends StatefulWidget {
  const DetailsPanel({
    super.key,
    required this.item,
    required this.maybeSelectedItem,
    required this.drivePrivacy,
    this.revisions,
    this.fileKey,
    required this.isSharePage,
  });

  final ArDriveDataTableItem item;
  final SelectedItem? maybeSelectedItem;
  final Privacy drivePrivacy;
  final List<FileRevision>? revisions;
  final SecretKey? fileKey;
  final bool isSharePage;

  @override
  State<DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<DetailsPanel> {
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      // Specify a key to ensure a new cubit is provided when the folder/file id changes.
      key: ValueKey(
        '${widget.item.driveId}${widget.item.id}',
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
            driveId: widget.item.driveId,
            maybeSelectedItem: widget.item,
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            arweave: context.read<ArweaveService>(),
            config: context.read<AppConfig>(),
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
                backgroundColor: ArDriveTheme.of(context)
                    .themeData
                    .tableTheme
                    .backgroundColor,
                contentPadding: const EdgeInsets.all(24),
                content: Column(
                  children: [
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
                          Expanded(
                            child: Text(
                              widget.item.name,
                              style: ArDriveTypography.body.buttonLargeBold(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      height: 48,
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
      children = _fileDetails();
    } else if (state is FsEntryInfoSuccess<Drive>) {
      children = _driveDetails(state);
    } else {
      children = [const Text('Loading...')];
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
      const SizedBox(
        height: 16,
      ),
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
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.lastUpdated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.dateCreated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: CopyButton(
          text: folder.entry.folder.driveId,
        ),
        itemTitle: appLocalizationsOf(context).driveID,
      ),
    ];
  }

  List<Widget> _driveDetails(FsEntryInfoSuccess state) {
    return [
      DetailsPanelItem(
        leading: CopyButton(text: widget.item.id),
        itemTitle: appLocalizationsOf(context).driveID,
      ),
      const SizedBox(
        height: 16,
      ),
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
      const SizedBox(
        height: 16,
      ),
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
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.lastUpdated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.dateCreated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
    ];
  }

  List<Widget> _fileDetails() {
    return [
      DetailsPanelItem(
        leading: CopyButton(text: widget.item.id),
        itemTitle: appLocalizationsOf(context).fileID,
      ),
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: Text(
          filesize(widget.item.size),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).size,
      ),
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.lastUpdated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: Text(
          yMMdDateFormatter.format(widget.item.dateCreated),
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: Text(
          widget.item.contentType,
          style: ArDriveTypography.body.buttonNormalRegular(),
        ),
        itemTitle: 'File type',
      ),
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: CopyButton(
          text: widget.item.driveId,
        ),
        itemTitle: appLocalizationsOf(context).metadataTxID,
      ),
      const SizedBox(
        height: 16,
      ),
      DetailsPanelItem(
        leading: CopyButton(
          text: (widget.item as FileDataTableItem).dataTxId,
        ),
        itemTitle: appLocalizationsOf(context).dataTxID,
      ),
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
          separatorBuilder: (context, index) => const SizedBox(
            height: 16,
          ),
          itemCount: state.revisions.length,
          itemBuilder: (context, index) {
            final revision = state.revisions[index];
            String title = '';
            String subtitle = '';

            if (revision is FolderRevisionWithTransaction) {
              switch (revision.action) {
                case RevisionAction.create:
                  title = 'Folder added to the drive';
                  break;
                case RevisionAction.rename:
                  title = 'Folder renamed to ${revision.name}';
                  break;
                case RevisionAction.move:
                  title = 'Folder moved';
                  break;
                default:
                  title = 'Folder was modified';
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
                  title = 'Drive created';
                  break;
                case RevisionAction.rename:
                  title = 'Drive renamed to ${revision.name}';
                  break;
                case RevisionAction.move:
                  title = 'Drive moved';
                  break;
                default:
                  title = 'Drive was modified';
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
        title = 'File added to the drive';
        leading = _DownloadOrPreview(
          isSharedFile: widget.isSharePage,
          privacy: widget.drivePrivacy,
          fileRevision: file,
          fileKey: key,
        );
        break;
      case RevisionAction.rename:
        title = 'File renamed to ${file.name}';
        break;
      case RevisionAction.move:
        title = 'File was moved';
        break;
      case RevisionAction.uploadNewVersion:
        title = 'File was updated';
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

  const CopyButton({
    Key? key,
    required this.text,
    this.size = 16,
    this.showCopyText = true,
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
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: widget.text));
        setState(() {
          _showCheck = true;
          if (mounted) {
            if (widget.showCopyText) {
              _overlayEntry = _createOverlayEntry(context);
              Overlay.of(context)?.insert(_overlayEntry!);
            }

            Future.delayed(const Duration(seconds: 2), () {
              setState(() {
                _showCheck = false;
                if (_overlayEntry != null && _overlayEntry!.mounted) {
                  _overlayEntry?.remove();
                }
              });
            });
          }
        });
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _showCheck
            ? ArDriveIcons.checkSuccess(
                size: widget.size,
                color: ArDriveTheme.of(context)
                    .themeData
                    .colors
                    .themeSuccessDefault,
              )
            : ArDriveIcons.copy(size: 16),
      ),
    );
  }

  OverlayEntry _createOverlayEntry(BuildContext parentContext) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset buttonPosition = button.localToGlobal(Offset.zero);
    final double buttonWidth = button.size.width;

    return OverlayEntry(
      builder: (context) => Positioned(
        left: buttonPosition.dx - 28,
        top: buttonPosition.dy - 40,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ArDriveTheme.of(parentContext)
                .themeData
                .dropdownTheme
                .backgroundColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Center(
              child: Material(
                child: Text(
                  'Copied!',
                  style: ArDriveTypography.body.smallRegular(),
                ),
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
    return InkWell(
      onTap: () {
        return downloadOrPreviewRevision(
          drivePrivacy: privacy,
          context: context,
          revision: fileRevision,
          fileKey: fileKey,
          isSharedFile: isSharedFile,
        );
      },
      child: ArDriveIcons.download(
        size: 16,
      ),
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
  if (drivePrivacy == 'private') {
    if (isSharedFile) {
      promptToDownloadSharedFile(
        context: context,
        revision: revision,
        fileKey: fileKey,
      );

      return;
    }

    promptToDownloadFileRevision(context: context, revision: revision);
  } else {
    context.read<DriveDetailCubit>().launchPreview(revision.dataTxId!);
  }
}

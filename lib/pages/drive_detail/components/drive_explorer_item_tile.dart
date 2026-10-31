import 'dart:async';
import 'dart:convert';

import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/components/pin_indicator.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/presentation/publish_to_web.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/drive_explorer/thumbnail/thumbnail_bloc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/components/item_menus.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_http/ardrive_http.dart';
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
            dimIfHidden(
                isHidden,
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: dataTableItem is FileDataTableItem
                      // The file name first: the name chip takes the room
                      // it leaves.
                      ? ArNSRowTitle(
                          text: name,
                          style: _titleStyle(typography),
                          title: _title(name, typography),
                          chip: (iconOnly) => ArNSNameChip(
                            dataTxId: dataTableItem.dataTxId,
                            hints: dataTableItem.assignedNames ?? const [],
                            isOwner: dataTableItem.isOwner,
                            iconOnly: iconOnly,
                          ),
                        )
                      : Row(
                          children: [
                            Flexible(child: _title(name, typography)),
                            if (dataTableItem is FolderDataTableItem)
                              PublishedToWebMark(
                                driveId: dataTableItem.driveId,
                                folderId: dataTableItem.id,
                              ),
                          ],
                        ),
                )),
            dimIfHidden(
                isHidden,
                Text(size,
                    style: _driveExplorerItemTileTextStyle(
                        isHidden, typography, colorTokens))),
            dimIfHidden(
              isHidden,
              ArDriveTooltip(
                message: formatDateTime(lastUpdated),
                child: Text(formatDate(lastUpdated),
                    style: _driveExplorerItemTileTextStyle(
                        isHidden, typography, colorTokens)),
              ),
            ),
            dimIfHidden(
              isHidden,
              ArDriveTooltip(
                message: formatDateTime(dateCreated),
                child: Text(formatDate(dateCreated),
                    style: _driveExplorerItemTileTextStyle(
                        isHidden, typography, colorTokens)),
              ),
            ),
            // The step the drives list uses for a row's secondary text, and
            // the one every other cell in this row already uses a sibling of.
            // This was the last cell here still on the old typography API, so
            // the two tables' rows now read from the same scale.
            dimIfHidden(
              isHidden,
              Text(
                license,
                style: typography.paragraphSmall(color: colorTokens.textMid),
              ),
            ),
          ],
        );
}

TextStyle _titleStyle(ArdriveTypographyNew typography) =>
    typography.paragraphNormal(fontWeight: ArFontWeight.semiBold);

Widget _title(String name, ArdriveTypographyNew typography) => ArDriveTooltip(
      message: name,
      child: Text(
        name,
        style: _titleStyle(typography),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        softWrap: false,
      ),
    );

TextStyle _driveExplorerItemTileTextStyle(bool isHidden,
        ArdriveTypographyNew typography, ArDriveColorTokens colorTokens) =>
    typography.paragraphNormal(fontWeight: ArFontWeight.semiBold);

/// How a hidden item is drawn: the whole row faded, its icon included, by the
/// same amount in both themes. A grey text colour can't do that - the light
/// theme's low text colour is a shade off its normal one - and the flat grey
/// these rows used was the same in both themes.
Widget dimIfHidden(bool isHidden, Widget child) =>
    isHidden ? Opacity(opacity: 0.45, child: child) : child;

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
      child: dimIfHidden(isHidden, _buildFileIcon(context)),
    );
  }

  Widget _buildFileIcon(BuildContext context) {
    // Only a file with a thumbnail has one to load: without, the request was
    // for `<gateway>/raw/null`, which failed into the icon below anyway.
    if (item is FileDataTableItem &&
        FileTypeHelper.isImage(item.contentType) &&
        (item as FileDataTableItem).thumbnail != null) {
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
                          );
                        },
                      ),
                    );
                  }

                  return Align(
                    alignment: Alignment.center,
                    child: getIconForContentType(
                      item.contentType,
                    ),
                  );
                },
              ),
            ),
            if (item.fileStatusFromTransactions != null)
              Positioned(
                right: 3,
                bottom: 3,
                child: FileStatusDot(
                  status: item.fileStatusFromTransactions!,
                ),
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
              // Making a thumbnail uploads one, which a publication visitor,
              // signed out, cannot do.
              onTap: PublicationMode.isOn
                  ? null
                  : () {
                      context
                          .read<ThumbnailRepository>()
                          .uploadThumbnail(fileId: item.id);
                    },
              child: getIconForContentType(
                item.contentType,
              ),
            ),
          ),
          if (item.fileStatusFromTransactions != null)
            Positioned(
              right: 3,
              bottom: 3,
              child: FileStatusDot(
                status: item.fileStatusFromTransactions!,
              ),
            ),
        ],
      ),
      backgroundColor: ArDriveTheme.of(context).themeData.backgroundColor,
    );
  }
}

/// The dot on a file's icon: amber waiting, green on chain, red not.
///
/// It says what it means now. An 8px circle in three colours is the only
/// report a file's own journey onto Arweave gets, and it was unlabelled:
/// confirming an upload is otherwise silent by design, since it asks about
/// one transaction and changes nothing about the drive.
///
/// The table and the grid both draw it, so both say what it means: the grid
/// had a dot of its own with no tooltip.
class FileStatusDot extends StatelessWidget {
  const FileStatusDot({super.key, required this.status});

  /// A [TransactionStatus].
  final String status;

  @override
  Widget build(BuildContext context) {
    late Color indicatorColor;
    late String meaning;

    switch (status) {
      case TransactionStatus.pending:
        indicatorColor =
            ArDriveTheme.of(context).themeData.colorTokens.statusWarningFg;
        meaning = appLocalizationsOf(context).fileStatusPendingTooltip;
        break;
      case TransactionStatus.confirmed:
        indicatorColor =
            ArDriveTheme.of(context).themeData.colorTokens.statusSuccessFg;
        meaning = appLocalizationsOf(context).fileStatusConfirmedTooltip;
        break;
      case TransactionStatus.failed:
        indicatorColor =
            ArDriveTheme.of(context).themeData.colorTokens.statusErrorFg;
        meaning = appLocalizationsOf(context).fileStatusFailedTooltip;
        break;
      default:
        indicatorColor = Colors.transparent;
        meaning = '';
    }

    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: indicatorColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    if (meaning.isEmpty) {
      return dot;
    }

    return ArDriveTooltip(message: meaning, child: dot);
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
    return ArDriveIcons.drive(
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
  } else if (FileTypeHelper.isJson(contentType)) {
    return ArDriveIcons.json(
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

  /// The menu button measures 34 (icon and padding); 40 leaves a little air.
  static const double _menuWidth = 40;

  /// The pin indicator is 32 wide and sits directly against the menu button.
  /// With the menu button the pair measures 66, in a slot of 76.
  static const double _pinWidth = 36;

  /// A ghost folder's **Fix** button and the menu button, measured in every
  /// language the app ships (the widest is Spanish at 139.4; Hindi is 137.0,
  /// English 102). `drive_explorer_item_tile_layout_test.dart` repeats the
  /// measurement and fails if a new label outgrows this. The test machine
  /// draws Hindi, Japanese and Chinese in a fallback face, so re-measure
  /// those on a real build when a label changes.
  static const double _ghostFolderWidth = 144;

  /// The width the trailing slot needs for [item]: the menu button, plus the
  /// **Fix** button or the pin indicator when the row has one.
  static double widthFor(ArDriveDataTableItem item) {
    if (item is FolderDataTableItem && item.isGhostFolder && item.isOwner) {
      return _ghostFolderWidth;
    }
    if (item is FileDataTableItem && item.pinnedDataOwnerAddress != null) {
      return _menuWidth + _pinWidth;
    }
    return _menuWidth;
  }

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
          ArDriveButtonNew(
            size: ArDriveButtonSize.compact,
            variant: ButtonVariant.primary,
            typography: ArDriveTypographyNew.of(context),
            onPressed: () => promptToReCreateFolder(
              context,
              ghostFolder: item,
            ),
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
    void moreInfo() => context.read<DriveDetailCubit>().selectDataItem(item);

    if (item is FolderDataTableItem) {
      return folderMenuItems(
        context,
        folder: item,
        drive: widget.drive,
        zipName: () {
          final driveDetail =
              context.read<DriveDetailCubit>().state as DriveDetailLoadSuccess;
          return item.id == driveDetail.currentDrive.rootFolderId
              ? driveDetail.currentDrive.name
              : item.name;
        },
        onMoreInfo: moreInfo,
        height: height,
      );
    }
    return fileMenuItems(
      context,
      file: item as FileDataTableItem,
      drive: widget.drive,
      onMoreInfo: moreInfo,
      height: height,
    );
  }
}

// TODO: @thiagocarvalhodev remove this and use the AppPlatform class or change the name of the method
bool isMobile(BuildContext context) {
  final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
  return isPortrait;
}

/// Downloads markdown file content and shows edit dialog
/// Supports both public and private files
Future<void> handleMarkdownFileEdit(
  BuildContext context,
  FileDataTableItem fileItem,
) async {
  // Whether the loader is up, so a failure closes only what this opened. A
  // failure before it opened, such as reading the drive, used to pop
  // whatever was underneath.
  var loaderOpen = false;
  try {
    // Get required services
    final driveDao = context.read<DriveDao>();
    final configService = context.read<ConfigService>();
    final arweaveService = context.read<ArweaveService>();
    final crypto = context.read<ArDriveCrypto>();
    final profileCubit = context.read<ProfileCubit>();

    // Get drive to check if it's private
    final drive =
        await driveDao.driveById(driveId: fileItem.driveId).getSingle();

    if (!context.mounted) return;

    // Through showArDriveDialog, so the activity tracker knows a dialog is
    // up while the file loads.
    unawaited(showArDriveDialog(
      context,
      content: const Center(
        child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
      ),
      barrierDismissible: false,
    ));
    loaderOpen = true;

    if (!context.mounted) return;

    // Use gateway for data request (same as other data fetches: preview, download, etc.)
    final gatewayUrl = configService.config.arweaveGatewayForDataRequest.url;
    final dataUrl = '$gatewayUrl/${fileItem.dataTxId}';

    // Fetch the file bytes using ArDriveHTTP
    final response = await ArDriveHTTP().getAsBytes(dataUrl);
    final dataBytes = response.data;

    if (dataBytes == null) {
      throw Exception('Failed to download file');
    }

    // Decrypt if private
    Uint8List bytesToDecode = dataBytes;
    final isPinFile = fileItem.pinnedDataOwnerAddress != null;

    if (drive.isPrivate && !isPinFile) {
      logger.d('Decrypting private markdown file: ${fileItem.name}');

      // Get profile key
      final profile = profileCubit.state;
      DriveKey? driveKey;

      if (profile is ProfileLoggedIn) {
        driveKey = await driveDao.getDriveKey(
          fileItem.driveId,
          profile.user.cipherKey,
        );
      } else {
        // For shared drives without profile
        driveKey = await driveDao.getDriveKeyFromMemory(fileItem.driveId);
      }

      if (driveKey == null) {
        throw Exception(
            'Unable to access drive key. Please ensure you have access to this private drive.');
      }

      // Derive file-specific key
      final fileKey = await driveDao.getFileKey(
        fileItem.fileId,
        driveKey.key,
      );

      // Get transaction metadata for cipher tags
      final transaction = await arweaveService.getTransactionDetails(
        fileItem.dataTxId,
      );

      if (transaction == null) {
        throw Exception('Failed to fetch file metadata');
      }

      // Decrypt the data
      try {
        final decryptedBytes = await crypto.decryptDataFromTransaction(
          transaction,
          dataBytes,
          fileKey,
        );
        bytesToDecode = decryptedBytes;
        logger.d('Successfully decrypted private file');
      } catch (e) {
        logger.e('Decryption failed', e);
        throw Exception(
            'Failed to decrypt file. The file may be corrupted or you may not have the correct permissions.');
      }
    }

    // Convert bytes to string
    final content = utf8.decode(bytesToDecode, allowMalformed: true);

    // Close loading indicator
    if (context.mounted) {
      Navigator.of(context).pop();
      loaderOpen = false;
    }

    // Show edit dialog
    if (context.mounted) {
      await promptToEditNote(
        context,
        driveId: fileItem.driveId,
        parentFolderId: fileItem.parentFolderId,
        fileId: fileItem.fileId,
        fileName: fileItem.name,
        fileContent: content,
        fileSize: fileItem.size ?? 0,
      );
    }
  } catch (e) {
    logger.e('Failed to load markdown file for editing', e);

    // Close the loader, if this got as far as opening it.
    if (loaderOpen && context.mounted) {
      Navigator.of(context).pop();
      loaderOpen = false;
    }

    // Show error dialog
    if (context.mounted) {
      // The error itself is in the log above. Its text is not for the user:
      // in a release build it can read "Instance of 'minified:Xy'".
      final strings = appLocalizationsOf(context);
      await showStandardDialog(
        context,
        title: strings.error,
        description: strings.couldNotLoadFile,
        actions: [
          ModalAction(
            action: () => Navigator.of(context).pop(),
            title: strings.ok,
          ),
        ],
      );
    }
  }
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
    this.onSync,
    this.driveIsSynced,
  });

  final ArDriveDataTableItem item;
  final bool withInfo;
  final Anchor alignment;
  final Drive? drive;

  /// Whether this device has [drive]'s contents, when the caller knows
  /// better than the drive record: the drives page counts a drive made and
  /// uploaded to here, whose block height is still 0. Its row menu and this
  /// one must agree.
  final bool? driveIsSynced;
  final bool isFileRevision;

  /// A drive's Sync, where the surface has its own way to sync it. Without
  /// one, Sync syncs the drive through the sync cubit.
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    // Watched, not read: the two drive-sync items below are drawn as
    // unavailable while a sync runs, so this menu has to be rebuilt when one
    // starts and when one stops.
    final isSyncing = driveSyncUnavailable(context.watch<SyncCubit>().state);
    // One row height for the menu and its rows, or the menu is sized for
    // rows shorter or taller than the ones it draws.
    final double height = isMobile(context) ? 44 : 48;
    final items =
        _getItems(item, context, withInfo, isFileRevision, isSyncing, height);
    final anchor = alignment;
    return ArDriveDropdown(
      // No maxHeight: the dropdown sizes itself from its items, counting a
      // divider at its own height rather than a row's. With this callback it
      // also opens up or down by the room there is and, when the menu is
      // taller than that room (a long menu at a large text size), fits it
      // and scrolls. The menu keeps the side it opens on.
      calculateVerticalAlignment: (opensUp) => Alignment(
        anchor is Aligned ? anchor.follower.x : 1,
        opensUp ? 1 : -1,
      ),
      height: height,
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

  /// Whether the explorer has [driveId] open with its contents: what the
  /// drive's menu means by synced, read only where an explorer is provided.
  static bool _explorerShows(BuildContext context, String driveId) {
    try {
      final state = context.read<DriveDetailCubit>().state;
      return state is DriveDetailLoadSuccess &&
          state.currentDrive.id == driveId;
    } on ProviderNotFoundException {
      return false;
    }
  }

  List<ArDriveDropdownItem> _getItems(
      ArDriveDataTableItem item,
      BuildContext context,
      bool withInfo,
      bool isFileRevision,
      bool isSyncing,
      double height) {
    void moreInfo() => context.read<DriveDetailCubit>().selectDataItem(item);
    final onMoreInfo = withInfo ? moreInfo : null;
    final drive = this.drive;

    if (item is FolderDataTableItem) {
      return folderMenuItems(
        context,
        folder: item,
        drive: drive,
        zipName: () => item.name,
        onMoreInfo: onMoreInfo,
        height: height,
      );
    }
    if (item is DriveDataItem) {
      if (drive == null) return const [];
      return driveMenuItems(
        context,
        drive: drive,
        isOwner: item.isOwner,
        isSynced: driveIsSynced ??
            ((drive.lastBlockHeight ?? 0) > 0 ||
                _explorerShows(context, drive.id)),
        isSyncing: isSyncing,
        onMoreInfo: onMoreInfo,
        onSync: onSync,
        height: height,
      );
    }
    if (!isFileRevision) {
      return fileMenuItems(
        context,
        file: item as FileDataTableItem,
        drive: drive,
        onMoreInfo: onMoreInfo,
        height: height,
      );
    }

    // A past version of a file: what it was, not what can be done to the
    // file now.
    final revision = item as FileDataTableItem;
    return [
      ArDriveDropdownItem(
        onClick: () =>
            promptToDownloadProfileFile(context: context, file: revision),
        content: _buildItem(
          appLocalizationsOf(context).download,
          ArDriveIcons.download(size: defaultIconSize),
          height: height,
        ),
      ),
      if (drive?.isPublic ?? false)
        ArDriveDropdownItem(
          onClick: () =>
              context.read<DriveDetailCubit>().launchPreview(revision.dataTxId),
          content: _buildItem(
            appLocalizationsOf(context).preview,
            ArDriveIcons.newWindow(size: defaultIconSize),
            height: height,
          ),
        ),
      ArDriveDropdownItem(
        onClick: () {
          Clipboard.setData(ClipboardData(text: revision.dataTxId));
        },
        content: _buildItem(
          appLocalizationsOf(context).copyDataTxID,
          ArDriveIcons.copy(size: defaultIconSize),
          height: height,
        ),
      ),
      if (revision.metadataTx != null)
        ArDriveDropdownItem(
          onClick: () {
            Clipboard.setData(ClipboardData(text: revision.metadataTx!.id));
          },
          content: _buildItem(
            appLocalizationsOf(context).copyMetadataTxID,
            ArDriveIcons.copy(size: defaultIconSize),
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

/// Re-asks the gateway whether a file's upload has landed.
///
/// A free function, and beside [hideFileDropdownItem] because it is here for
/// the same reason: this menu exists twice - once on the row and once in the
/// details panel - and an item written into one of those copies is an item half
/// the app does not have. That is not hypothetical. The first version of this
/// went into the row kebab only, so the details panel, which is where somebody
/// staring at a pending status is most likely to be, could not do anything
/// about it.
///
/// Only ever offered on a file that is actually waiting: a confirmed file has
/// nothing to check, and an item that is present and does nothing is worse than
/// one that is absent.
ArDriveDropdownItem checkUploadStatusDropdownItem(
  BuildContext context, {
  double? height,
}) {
  return ArDriveDropdownItem(
    onClick: () async {
      // Both read before the await: the tile can be gone by the time the
      // gateway answers - the row it sits in redraws whenever the folder does -
      // and a context read afterwards is a context that may no longer be
      // mounted.
      final messenger = ScaffoldMessenger.of(context);
      final checked = appLocalizationsOf(context).checkedUploadStatus;

      final refreshed =
          await context.read<SyncCubit>().refreshPendingStatuses();

      // Refused because a sync is already running, or it failed. Either way the
      // row keeps the status it had and says nothing it cannot stand behind.
      if (!refreshed) {
        return;
      }

      showArDriveToast(messenger, text: checked);
    },
    content: ArDriveDropdownItemTile(
      name: appLocalizationsOf(context).checkUploadStatus,
      icon: ArDriveIcons.refresh(size: defaultIconSize),
      height: height,
    ),
  );
}

ArDriveDropdownItem hideFileDropdownItem(
  BuildContext context,
  ArDriveDataTableItem item, {
  double? height,
}) {
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
      height: height,
    ),
  );
}

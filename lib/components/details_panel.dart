import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/snapshots_tab/snapshots_tab.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/dotted_line.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/fs_entry_license_form.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/components/license_details_popover.dart';
import 'package:ardrive/components/pin_indicator.dart';
import 'package:ardrive/components/sizes.dart';
import 'package:ardrive/components/truncated_address.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive/drive_explorer/thumbnail_creation/page/thumbnail_creation_modal.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/presentation/publish_to_web.dart';
import 'package:ardrive/publication/presentation/publication_chrome.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/is_supported_image_type_for_preview.dart';
import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../blocs/blocs.dart';
import '../utils/file_revision_base.dart';

/// The drive explorer's info panel: preview, details and activity for the item
/// that is selected in a drive.
///
/// This used to render the share page as well, behind an `isSharePage` flag
/// that reshaped almost every branch in the file. The recipient's page is its
/// own widget tree now (`lib/pages/shared_file/`), and nothing outside a signed
/// in drive builds this panel, so the flag - and the shared-file inputs that
/// only ever arrived with it - are gone.
class DetailsPanel extends StatefulWidget {
  const DetailsPanel({
    super.key,
    required this.item,
    this.currentDrive,
    this.onPreviousImageNavigation,
    this.onNextImageNavigation,
    required this.canNavigateThroughImages,
    this.onClose,
    this.onSync,
  });

  final ArDriveDataTableItem item;
  final Drive? currentDrive;
  final Function()? onPreviousImageNavigation;
  final Function()? onNextImageNavigation;
  final bool canNavigateThroughImages;

  /// Closes the panel, for a panel that is not the explorer's.
  ///
  /// With it, the toolbar is drawn for [currentDrive] and closes through
  /// this. Without it, the toolbar follows the explorer's own state, as it
  /// always has. The drives list keeps that explorer alive holding whichever
  /// drive was last open, so a panel beside the list reading it would offer
  /// to share and rename the wrong drive.
  final VoidCallback? onClose;

  /// Syncs a drive this device has never synced, offered where its size and
  /// contents would be. Each place the panel lives has its own way to sync -
  /// the explorer's unsynced card, the drives list's menu - and the panel
  /// takes whichever it is given. Without one, the panel only says so.
  final VoidCallback? onSync;

  @override
  State<DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<DetailsPanel> {
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      // Specify a key to ensure a new cubit is provided when the folder/file id
      // changes.
      key: ValueKey(
        '${widget.item.driveId}${widget.item.id}${widget.item.name}',
      ),
      providers: [
        BlocProvider<FsEntryInfoCubit>(
          create: (context) => FsEntryInfoCubit(
            driveId: widget.item.driveId,
            maybeSelectedItem: widget.item,
            driveDao: context.read<DriveDao>(),
            licenseService: context.read<LicenseService>(),
            arweave: context.read<ArweaveService>(),
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
            configService: context.read<ConfigService>(),
          ),
        )
      ],
      child: BlocBuilder<FsEntryPreviewCubit, FsEntryPreviewState>(
          builder: (context, previewState) {
        return BlocBuilder<FsEntryInfoCubit, FsEntryInfoState>(
          builder: (context, infoState) {
            return ScreenTypeLayout.builder(
              // The panel's content is the same either way; only the axis it
              // is laid out on differs.
              desktop: (context) => Row(
                children: _buildContent(
                  previewState: previewState,
                  infoState: infoState,
                  context: context,
                ),
              ),
              mobile: (context) => Column(
                children: _buildContent(
                  previewState: previewState,
                  infoState: infoState,
                  context: context,
                ),
              ),
            );
          },
        );
      }),
    );
  }

  List<Widget> _buildContent({
    required FsEntryPreviewState previewState,
    required FsEntryInfoState infoState,
    required BuildContext context,
  }) {
    // [FsEntryPreviewOversized] extends [FsEntryPreviewUnavailable], so it has
    // to be excluded here or an over-limit file loses its Preview tab entirely
    // instead of showing the tab that explains the file is too large to
    // preview (F10).
    final isPreviewUnavailable = previewState is FsEntryPreviewUnavailable &&
        previewState is! FsEntryPreviewOversized;
    final typography = ArDriveTypographyNew.of(context);

    final tabs = [
      if (!isPreviewUnavailable)
        ArDriveTab(
          Tab(
            child: Text(
              appLocalizationsOf(context).itemPreviewEmphasized,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
              ),
            ),
          ),
          Column(
            children: [
              Expanded(child: _buildPreview(previewState, context: context)),
            ],
          ),
        ),
      ArDriveTab(
        Tab(
          child: Text(
            appLocalizationsOf(context).itemDetailsEmphasized,
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.bold,
            ),
          ),
        ),
        _buildDetails(infoState),
      ),
      ArDriveTab(
        Tab(
          child: Text(
            appLocalizationsOf(context).itemActivityEmphasized,
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.bold,
            ),
          ),
        ),
        BlocProvider(
          create: (context) => FsEntryActivityCubit(
            driveId: widget.item.driveId,
            maybeSelectedItem: widget.item,
            driveDao: context.read<DriveDao>(),
            arweave: context.read<ArweaveService>(),
            profileCubit: context.read<ProfileCubit>(),
          ),
          child: BlocBuilder<FsEntryActivityCubit, FsEntryActivityState>(
            builder: (context, state) {
              return _buildActivity(state);
            },
          ),
        ),
      ),
      // Snapshots tab - only shown for drives, not for files or folders
      if (widget.item is DriveDataItem && widget.currentDrive != null)
        ArDriveTab(
          Tab(
            child: Text(
              appLocalizationsOf(context).snapshotsEmphasized,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
              ),
            ),
          ),
          BlocProvider(
            create: (context) {
              final config = context.read<ConfigService>().config;
              final arweave = context.read<ArweaveService>();
              return FsEntrySnapshotsCubit(
                driveId: widget.item.driveId,
                ownerAddress: widget.currentDrive!.ownerAddress,
                arweaveService: arweave,
                // Drive state artifacts are snapshots to the user too, so the
                // tab lists them wherever the build reads or publishes them.
                driveStateDiscovery: config.enableSyncFromDriveState ||
                        config.enableDriveStatePublishing
                    ? GraphQLDriveStateDiscovery(
                        graphQLRetry: arweave.graphQLRetry,
                      )
                    : null,
              );
            },
            child: SnapshotsTab(drive: widget.currentDrive!),
          ),
        ),
    ];

    return [
      Flexible(
        flex: 1,
        child: ArDriveCard(
          borderRadius:
              AppPlatform.isMobile || AppPlatform.isMobileWeb() ? 0 : null,
          backgroundColor:
              ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            children: [
              ScreenTypeLayout.builder(
                desktop: (context) => Column(
                  children: [
                    if (widget.onClose != null && widget.currentDrive != null)
                      DetailsPanelToolbar(
                        item: widget.item,
                        drive: widget.currentDrive!,
                        onClose: widget.onClose!,
                      )
                    else
                      BlocBuilder<DriveDetailCubit, DriveDetailState>(
                        builder: (context, driveDetailState) {
                          if (driveDetailState is DriveDetailLoadSuccess) {
                            return DetailsPanelToolbar(
                              item: widget.item,
                              drive: driveDetailState.currentDrive,
                              onClose: () => context
                                  .read<DriveDetailCubit>()
                                  .toggleSelectedItemDetails(),
                            );
                          }
                          // For other states, without an onClose of their
                          // own, don't show the toolbar
                          return const SizedBox.shrink();
                        },
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
                      child: ArDriveTooltip(
                        message: widget.item.name,
                        child: Text(
                          widget.item.name,
                          style: typography.paragraphLarge(
                            fontWeight: ArFontWeight.semiBold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (widget.item is FileDataTableItem &&
                        (widget.item as FileDataTableItem)
                                .pinnedDataOwnerAddress !=
                            null) ...[
                      const PinIndicator(
                        size: 32,
                      ),
                    ],
                    if (widget.item is FileDataTableItem &&
                        isSupportedImageTypeForPreview(
                            widget.item.contentType) &&
                        (widget.item as FileDataTableItem).thumbnail == null &&
                        widget.item.isOwner) ...[
                      ArDriveIconButton(
                        icon: ArDriveIcons.image(),
                        tooltip: 'Create thumbnail',
                        onPressed: () {
                          showArDriveDialog(
                            context,
                            content: BlocProvider.value(
                              value: context.read<DriveDetailCubit>(),
                              child: ThumbnailCreationModal(
                                fileDataTableItem:
                                    widget.item as FileDataTableItem,
                              ),
                            ),
                          );
                        },
                      )
                    ],
                    if (widget.currentDrive != null)
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
                // A card on the panel, in both themes.
                child: ArDriveTabView(
                  key: Key(widget.item.id + tabs.length.toString()),
                  tabs: tabs,
                  backgroundColor: ArDriveTheme.of(context)
                      .themeData
                      .colorTokens
                      .containerRaised,
                  unselectedTabColor: ArDriveTheme.of(context)
                      .themeData
                      .colorTokens
                      .containerRaised,
                  unselectedLabelColor:
                      ArDriveTheme.of(context).themeData.colorTokens.textHigh,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildPreview(
    FsEntryPreviewState previewState, {
    required BuildContext context,
  }) {
    return Align(
      alignment: Alignment.center,
      child: FsEntryPreviewWidget(
        key: ValueKey(widget.item.id),
        state: previewState,
        isSharePage: false,
        onNextImageNavigation: widget.onNextImageNavigation,
        onPreviousImageNavigation: widget.onPreviousImageNavigation,
        canNavigateThroughImages: widget.canNavigateThroughImages,
        previewCubit: context.read<FsEntryPreviewCubit>(),
      ),
    );
  }

  Widget _buildDetails(FsEntryInfoState state) {
    late List<Widget> children;
    if (state is FsEntryInfoSuccess<FolderNode>) {
      children = _folderDetails(state);
    } else if (state is FsEntryFileInfoSuccess) {
      children = _fileDetails(state);
    } else if (state is FsEntryInfoSuccess<Drive>) {
      children = _driveDetails(state);
    } else if (state is FsEntryUnsyncedDriveInfo) {
      children = _unsyncedDriveDetails(state);
    } else if (state is FsEntryInfoFailure) {
      // Not the spinner: a failure is finished, and a spinner says it is not.
      children = [
        Text(
          appLocalizationsOf(context).detailsCouldNotBeLoaded,
          style: ArDriveTypographyNew.of(context).paragraphNormal(
            color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
          ),
        ),
      ];
    } else {
      children = [
        const Center(
          child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
        )
      ];
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 28,
        vertical: 16,
      ),
      children: children,
    );
  }

  List<Widget> _folderDetails(
    FsEntryInfoSuccess<FolderNode> folder,
  ) {
    final typography = ArDriveTypographyNew.of(context);
    return [
      DetailsPanelItem(
        leading: _IdValue(id: folder.entry.folder.id),
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
          style: typography.paragraphNormal(),
        ),
        itemTitle: appLocalizationsOf(context).itemContains,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateTime(widget.item.lastUpdated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateTime(widget.item.dateCreated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: _IdValue(id: folder.entry.folder.driveId),
        itemTitle: appLocalizationsOf(context).driveID,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: _IdValue(id: folder.metadataTxId, isTransaction: true),
        itemTitle: appLocalizationsOf(context).metadataTxID,
      ),
    ];
  }

  List<Widget> _driveDetails(FsEntryInfoSuccess state) {
    final typography = ArDriveTypographyNew.of(context);

    return [
      DetailsPanelItem(
        leading: _IdValue(id: widget.item.id),
        itemTitle: appLocalizationsOf(context).driveID,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          filesize((state as FsEntryDriveInfoSuccess)
              .rootFolderTree
              .computeFolderSize()),
          style: typography.paragraphNormal(),
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
          style: typography.paragraphNormal(),
        ),
        itemTitle: appLocalizationsOf(context).itemContains,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateTime(widget.item.lastUpdated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateTime(widget.item.dateCreated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: _IdValue(id: state.metadataTxId, isTransaction: true),
        itemTitle: appLocalizationsOf(context).metadataTxID,
      ),
      if (state.drive.isPrivate) ...[
        sizedBoxHeight16px,
        DetailsPanelItem(
          leading: Text(
            widget.item.signatureType ?? '?',
            textAlign: TextAlign.right,
          ),
          // TODO: Localize
          itemTitle: 'Signature type',
        ),
      ],
    ];
  }

  /// A drive known only from the drive list: everything that is known, and
  /// where its size and contents would be, why they are not.
  List<Widget> _unsyncedDriveDetails(FsEntryUnsyncedDriveInfo state) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final onSync = widget.onSync;

    return [
      DetailsPanelItem(
        leading: _IdValue(id: widget.item.id),
        itemTitle: appLocalizationsOf(context).driveID,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          appLocalizationsOf(context).driveNeverSynced,
          style: typography.paragraphNormal(color: colorTokens.textMid),
        ),
        itemTitle: appLocalizationsOf(context).size,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateTime(state.drive.lastUpdated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateTime(state.drive.dateCreated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      if (state.drive.isPrivate) ...[
        sizedBoxHeight16px,
        DetailsPanelItem(
          leading: Text(
            widget.item.signatureType ?? '?',
            textAlign: TextAlign.right,
          ),
          // TODO: Localize
          itemTitle: 'Signature type',
        ),
      ],
      const SizedBox(height: 24),
      Text(
        appLocalizationsOf(context).driveInfoNeverSyncedDetail,
        style: typography.paragraphNormal(color: colorTokens.textMid),
      ),
      if (onSync != null && !PublicationMode.isOn) ...[
        const SizedBox(height: 16),
        _syncThisDriveButton(onSync),
      ],
    ];
  }

  /// Licensing writes to Arweave, so it is offered only to a signed-in owner
  /// of a file that is not pinned: the row menu gates it the same way. The
  /// sign-in check matters on its own, because search builds its items as
  /// owned whatever the drive.
  bool _canLicense(BuildContext context, FileDataTableItem item) =>
      item.pinnedDataOwnerAddress == null &&
      item.isOwner &&
      context.read<ProfileCubit>().state is ProfileLoggedIn;

  List<Widget> _fileDetails(FsEntryInfoState state) {
    final item = widget.item as FileDataTableItem;
    String? pinnedDataOwnerAddress = item.pinnedDataOwnerAddress;

    final typography = ArDriveTypographyNew.of(context);
    final driveState = context.read<DriveDetailCubit>().state;
    final nameable = arnsNameableItem(
      context,
      item: item,
      drive: widget.currentDrive ??
          (driveState is DriveDetailLoadSuccess
              ? driveState.currentDrive
              : null),
    );

    return [
      if (nameable != null) ...[
        ArNSNameSection(item: nameable),
        sizedBoxHeight16px,
      ],
      DetailsPanelItem(
        leading: _IdValue(id: item.id),
        itemTitle: appLocalizationsOf(context).fileID,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          filesize(item.size),
          style: typography.paragraphNormal(),
        ),
        itemTitle: appLocalizationsOf(context).size,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateTime(item.lastUpdated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateTime(item.dateCreated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          item.contentType,
          textAlign: TextAlign.right,
          style: typography.paragraphNormal(),
        ),
        itemTitle: appLocalizationsOf(context).fileType,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: _IdValue(id: item.dataTxId, isTransaction: true),
        itemTitle: appLocalizationsOf(context).dataTxID,
      ),
      sizedBoxHeight16px,
      if (state is FsEntryInfoSuccess) ...[
        DetailsPanelItem(
          leading: _IdValue(id: state.metadataTxId, isTransaction: true),
          itemTitle: appLocalizationsOf(context).metadataTxID,
        ),
        sizedBoxHeight16px,
      ],
      if (item.fallbackTxId != null) ...[
        DetailsPanelItem(
          leading: _IdValue(id: item.fallbackTxId!, isTransaction: true),
          itemTitle: appLocalizationsOf(context).manifestFallbackTxID,
        ),
        sizedBoxHeight16px,
      ],
      if (state is FsEntryFileInfoSuccess)
        DetailsPanelItem(
          itemTitle: 'License',
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              state.licenseState != null
                  ? LicenseDetailsPopoverButton(
                      licenseState: state.licenseState!,
                      fileItem: item,
                      updateButton: _canLicense(context, item),
                      anchor: const Aligned(
                        follower: Alignment.bottomRight,
                        target: Alignment.topRight,
                        // Shift to the edge of the screen on Mobile
                        backup: Aligned(
                          follower: Alignment.bottomRight,
                          target: Alignment.topRight,
                          offset: Offset(48, 0),
                        ),
                      ),
                    )
                  : _canLicense(context, item)
                      ? ArDriveButtonNew(
                          text: 'Add',
                          typography: ArDriveTypographyNew.of(context),
                          size: ArDriveButtonSize.compact,
                          onPressed: () => promptToLicense(
                            context,
                            driveId: item.driveId,
                            selectedItems: [item],
                          ),
                        )
                      : Text(
                          'None',
                          textAlign: TextAlign.right,
                          style: typography.paragraphNormal(),
                        ),
            ],
          ),
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
    if (state is FsEntryActivitySuccess) {
      if (state.revisions.isNotEmpty) {
        final versions = fileVersionNumbers(state.revisions);

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
                case RevisionAction.hide:
                  title = appLocalizationsOf(context).folderWasHidden;
                  break;
                case RevisionAction.unhide:
                  title = appLocalizationsOf(context).folderWasUnhidden;
                  break;
                default:
                  title = appLocalizationsOf(context).folderWasModified;
              }
              subtitle = formatDateTime(revision.dateCreated);

              return DetailsPanelItem(
                itemSubtitle: subtitle,
                itemTitle: title,
                expandLeading: false,
              );
            } else if (revision is FileRevisionWithLicenseAndTransactions) {
              final file = ARFSFactory()
                  .getARFSFileFromFileRevisionWithLicenseAndTransactions(
                      revision);
              final licenseState = revision.license == null
                  ? null
                  : context
                      .read<LicenseService>()
                      .fromCompanion(revision.license!.toCompanion(true));

              return _buildFileActivity(
                file,
                licenseState,
                revision.action,
                fileRevisionWithLicenseAndTransactions: revision,
                version: versions[index],
              );
            } else if (revision is DriveRevisionWithTransaction) {
              return _driveActivityItem(
                action: revision.action,
                name: revision.name,
                date: revision.dateCreated,
              );
            } else if (revision is DriveRevisionsCompanion) {
              // Read from the network for a drive not synced here.
              return _driveActivityItem(
                action: revision.action.value,
                name: revision.name.value,
                date: revision.dateCreated.value,
              );
            }

            return const SizedBox();
          },
        );
      }
    }

    if (state is FsEntryActivityDriveNotSynced) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        children: [
          Text(
            appLocalizationsOf(context).driveActivityNeedsSync,
            style: ArDriveTypographyNew.of(context).paragraphNormal(
              color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
            ),
          ),
          if (widget.onSync != null && !PublicationMode.isOn) ...[
            const SizedBox(height: 16),
            _syncThisDriveButton(widget.onSync!),
          ],
        ],
      );
    }

    // Said, the way the details tab says it: this used to read "Loading..."
    // for good when the history was empty or could not be read.
    if (state is FsEntryActivitySuccess || state is FsEntryActivityFailure) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        children: [
          Text(
            state is FsEntryActivityFailure
                ? appLocalizationsOf(context).activityCouldNotBeLoaded
                : appLocalizationsOf(context).activityNoneRecorded,
            style: ArDriveTypographyNew.of(context).paragraphNormal(
              color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
            ),
          ),
        ],
      );
    }

    return const Center(child: ArDriveSpinner(size: ArDriveSpinnerSize.large));
  }

  Widget _driveActivityItem({
    required String action,
    required String name,
    required DateTime date,
  }) {
    final String title;
    switch (action) {
      case RevisionAction.create:
        title = appLocalizationsOf(context).driveWasCreatedWithName(name);
        break;
      case RevisionAction.rename:
        title = appLocalizationsOf(context).driveWasRenamed(name);
        break;
      case RevisionAction.hide:
        title = appLocalizationsOf(context).driveWasHidden;
        break;
      case RevisionAction.unhide:
        title = appLocalizationsOf(context).driveWasUnhidden;
        break;
      default:
        title = appLocalizationsOf(context).driveWasModified;
    }

    return DetailsPanelItem(
      itemSubtitle: formatDateTime(date),
      itemTitle: title,
      expandLeading: false,
    );
  }

  /// Offered, never done for the reader: opening a drive's details is not
  /// asking for it to sync. One sync at a time, so it waits out a running
  /// one - the same rule as the drive's own card.
  Widget _syncThisDriveButton(VoidCallback onSync) {
    return Builder(
      builder: (context) {
        final isSyncing = context.watch<SyncCubit>().state is SyncInProgress;

        return Align(
          alignment: Alignment.centerLeft,
          child: ArDriveButtonNew(
            text: appLocalizationsOf(context).syncThisDrive,
            typography: ArDriveTypographyNew.of(context),
            variant: ButtonVariant.primary,
            maxWidth: 160,
            isDisabled: isSyncing,
            onPressed: isSyncing ? null : onSync,
          ),
        );
      },
    );
  }

  Widget _buildFileActivity(
    ARFSFileEntity file,
    LicenseState? licenseState,
    String action, {
    FileRevisionWithLicenseAndTransactions?
        fileRevisionWithLicenseAndTransactions,
    int? version,
  }) {
    late String title;
    String? subtitle;
    Widget? leading;

    // A revision that brought new data says how big it was, so versions can
    // be told apart.
    final carriesData = action == RevisionAction.create ||
        action == RevisionAction.uploadNewVersion;

    switch (action) {
      case RevisionAction.create:
        if (file.pinnedDataOwnerAddress != null) {
          title = appLocalizationsOf(context).fileWasPinnedToTheDrive;
        } else {
          title = appLocalizationsOf(context).fileWasCreatedWithName(file.name);
        }
        leading = _DownloadOrPreview(
          fileRevision: file,
        );

        if (fileRevisionWithLicenseAndTransactions != null) {
          leading = _FileRevisionOptions(
            fileRevision: FileRevisionBase.fromFileRevisionWithLicense(
                fileRevisionWithLicenseAndTransactions),
            drive: widget.currentDrive,
          );
        }

        break;
      case RevisionAction.rename:
        title = appLocalizationsOf(context).fileWasRenamed(file.name);
        break;
      case RevisionAction.move:
        title = appLocalizationsOf(context).fileWasMoved;
        break;
      case RevisionAction.uploadNewVersion:
        title = version == null
            ? appLocalizationsOf(context).fileHadANewRevision
            : appLocalizationsOf(context).fileVersionWasUploaded(version);
        leading = _DownloadOrPreview(
          fileRevision: file,
        );

        if (fileRevisionWithLicenseAndTransactions != null) {
          leading = _FileRevisionOptions(
            fileRevision: FileRevisionBase.fromFileRevisionWithLicense(
                fileRevisionWithLicenseAndTransactions),
            drive: widget.currentDrive,
          );
        }

        break;
      case RevisionAction.assignName:
        final names = file.assignedNames ?? const [];
        title = names.isEmpty
            ? appLocalizationsOf(context).arnsActivityNameRemoved
            : appLocalizationsOf(context)
                .arnsActivityNameAssigned(arnsHostFor(names.last));
        break;
      case RevisionAction.assertLicense:
        if (licenseState == null) {
          title = 'File had license updated';
          // TODO: Localize
          // title = appLocalizationsOf(context).fileHadALicenseUpdated;
        } else {
          title = 'File had license updated to ${licenseState.meta.shortName}';
          // TODO: Localize
          // title = appLocalizationsOf(context).fileHadALicenseUpdated(licenseState.meta.shortName);
        }
        break;
      case RevisionAction.hide:
        title = appLocalizationsOf(context).fileWasHidden;
        break;
      case RevisionAction.unhide:
        title = appLocalizationsOf(context).fileWasUnhidden;
        break;
      case RevisionAction.bulkImport:
        if (file.importSource == null && file.originalOwner == null) {
          title = 'Imported from manifest';
        } else {
          final typography = ArDriveTypographyNew.of(context);
          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          flex: 1,
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Imported from manifest ',
                                  style: typography.paragraphNormal(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: colorTokens.textHigh,
                                  ),
                                ),
                                WidgetSpan(
                                  child: ArDriveClickArea(
                                    child: _TxIdTextLink(
                                      txId: file.importSource!,
                                      customUrl:
                                          '${configService.config.arweaveGatewayForDataRequest.url}/raw/${file.importSource}',
                                    ),
                                  ),
                                ),
                                TextSpan(
                                  text: ' and owner ',
                                  style: typography.paragraphNormal(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: colorTokens.textHigh,
                                  ),
                                ),
                                // Opens in a new tab; the tooltip has the
                                // whole address.
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: ArDriveTooltip(
                                    message: file.originalOwner!,
                                    child: ArDriveLink(
                                      text: truncateString(
                                        file.originalOwner!,
                                        offsetStart: 6,
                                        offsetEnd: 6,
                                      ),
                                      // An address, so monospace.
                                      style: typography.code(),
                                      color: colorTokens.textHigh,
                                      external: true,
                                      onTap: () => openUrl(
                                          url:
                                              'https://viewblock.io/arweave/address/${file.originalOwner}'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 4,
                          ),
                        ),
                        Flexible(
                          flex: 3,
                          child: Text(
                            formatDateTime(file.unixTime),
                            style: typography.paragraphSmall(
                              color: colorTokens.textMid,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 18,
              ),
              HorizontalDottedLine(
                color: ArDriveTheme.of(context).themeData.colorTokens.strokeLow,
                width: double.maxFinite,
              ),
            ],
          );
        }

      default:
        title = appLocalizationsOf(context).fileWasModified;
    }
    // Joined with non-breaking spaces, so a narrow panel moves the size to a
    // line of its own rather than splitting "1.27" from "KiB".
    subtitle = carriesData
        ? '${formatDateTime(file.unixTime)} · '
            '${filesize(file.size).replaceAll(' ', ' ')}'
        : formatDateTime(file.unixTime);

    return DetailsPanelItem(
      leading: leading ?? const SizedBox(),
      itemTitle: title,
      itemSubtitle: subtitle,
      expandLeading: false,
    );
  }
}

class _TxIdTextLink extends StatelessWidget {
  const _TxIdTextLink({
    required this.txId,
    this.customUrl,
  });

  final String txId;
  final String? customUrl;

  @override
  Widget build(BuildContext context) {
    return ArDriveClickArea(
      child: GestureDetector(
        onTap: () {
          openUrl(url: customUrl ?? 'https://viewblock.io/arweave/tx/$txId');
        },
        child: ArDriveTooltip(
          message: txId,
          // A link the way the panel's other address is one: see
          // [TruncatedAddress]. Monospace has one weight, so the link colour
          // alone marks it.
          child: ArDriveIdText(
            shortenId(txId),
            style: ArDriveTypographyNew.of(context).code(
              color: ArDriveTheme.of(context).themeData.colorTokens.textLink,
            ),
          ),
        ),
      ),
    );
  }
}

/// An ID in the details: shortened, in full in its tooltip, and with a button
/// that copies it.
///
/// A transaction opens in a block explorer. A file, folder or drive ID has no
/// page of its own there, so it is only text. Those rows used to show the
/// copy button alone, with nothing to say which ID it would copy.
class _IdValue extends StatelessWidget {
  const _IdValue({required this.id, this.isTransaction = false});

  final String id;
  final bool isTransaction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: isTransaction
              ? _TxIdTextLink(txId: id)
              : ArDriveTooltip(
                  message: id,
                  child: ArDriveIdText(
                    shortenId(id),
                    style: ArDriveTypographyNew.of(context).code(),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        CopyButton(text: id),
      ],
    );
  }
}

/// An ID short enough for a row of the details: its first six characters and
/// its last four, enough to tell two apart.
@visibleForTesting
String shortenId(String id) =>
    id.length <= 13 ? id : truncateString(id, offsetStart: 6, offsetEnd: 4);

/// The version number of each revision in a file's history that uploaded
/// data, by its index in [revisions], which lists the newest first.
///
/// Counted from the oldest: the first upload is version 1, and each new
/// version adds one. A rename or a move is not a version. Anything that is not
/// a file's revision has none.
@visibleForTesting
Map<int, int> fileVersionNumbers(List<Object?> revisions) {
  final versions = <int, int>{};
  var version = 0;

  for (var index = revisions.length - 1; index >= 0; index--) {
    final revision = revisions[index];

    if (revision is FileRevisionWithLicenseAndTransactions &&
        (revision.action == RevisionAction.create ||
            revision.action == RevisionAction.uploadNewVersion)) {
      versions[index] = ++version;
    }
  }

  return versions;
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
    this.expandLeading = true,
  });

  final String itemTitle;
  final String? itemSubtitle;
  final Widget? leading;
  final bool expandLeading;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    flex: 1,
                    child: Text(
                      // "ID" stays on the line of the word before it, so a
                      // narrow panel wraps "Metadata / transaction ID" rather
                      // than leaving "ID" on a line of its own.
                      itemTitle.replaceAll(' ID', '\u00A0ID'),
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.bold,
                      ),
                      maxLines: 4,
                    ),
                  ),
                  if (itemSubtitle != null)
                    Flexible(
                      flex: 3,
                      child: Text(
                        itemSubtitle!,
                        style: typography.paragraphSmall(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colorTokens
                              .textMid,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (leading != null)
              Expanded(
                flex: expandLeading ? 6 : 1,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: leading!,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(
          height: 18,
        ),
        HorizontalDottedLine(
          color: ArDriveTheme.of(context).themeData.colorTokens.strokeLow,
          width: double.maxFinite,
        ),
      ],
    );
  }
}

class _DownloadOrPreview extends StatelessWidget {
  const _DownloadOrPreview({
    required this.fileRevision,
  });

  final ARFSFileEntity fileRevision;

  @override
  Widget build(BuildContext context) {
    return ArDriveIconButton(
      onPressed: () {
        return downloadOrPreviewRevision(
          context: context,
          revision: fileRevision,
        );
      },
      tooltip: appLocalizationsOf(context).download,
      icon: ArDriveIcons.download(size: 20),
    );
  }
}

class _FileRevisionOptions extends StatelessWidget {
  const _FileRevisionOptions({
    required this.fileRevision,
    required this.drive,
  });

  final FileRevisionBase fileRevision;

  /// The drive the revision belongs to, so the menu can tell a public
  /// revision, which may open in a new window, from a private one, whose
  /// bytes the gateway serves encrypted.
  final Drive? drive;

  @override
  Widget build(BuildContext context) {
    final item = DriveDataTableItemMapper.fromRevision(fileRevision, true);

    return EntityActionsMenu(
      item: item,
      drive: drive,
      isFileRevision: true,
      withInfo: false,
      // bottom right to top left
      alignment: const Aligned(
        follower: Alignment.bottomRight,
        target: Alignment.topLeft,
      ),
    );
  }
}

void downloadOrPreviewRevision({
  required BuildContext context,
  required ARFSFileEntity revision,
}) {
  promptToDownloadFileRevision(context: context, revision: revision);
}

/// Whether the toolbar offers to download [item], given what the panel has
/// read about it.
///
/// A file or a folder is always offered. A drive is offered only once the read
/// of the local database says this device knows its contents: a drive that has
/// never synced here has none, and until the read comes back neither has any
/// other. An offer that may be withdrawn a moment later is worse than one that
/// arrives late.
@visibleForTesting
bool offersDownload(ArDriveDataTableItem item, FsEntryInfoState info) =>
    item is! DriveDataItem || info is FsEntryDriveInfoSuccess;

class DetailsPanelToolbar extends StatelessWidget {
  const DetailsPanelToolbar({
    super.key,
    required this.item,
    required this.drive,
    required this.onClose,
  });

  final ArDriveDataTableItem item;

  /// The drive the item is in. Handed in rather than read off the explorer,
  /// so a panel that is not the explorer's acts on the right one.
  final Drive drive;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // A local so that type promotion works on it: a widget field cannot be
    // promoted, and the share icon has to ask a folder whether it is a ghost.
    final item = this.item;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: ArDriveTheme.of(context).themeData.colorTokens.strokeLow,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const SizedBox(
            width: 16,
          ),
          if (item is FileDataTableItem ||
              item is DriveDataItem ||
              // Not a ghost folder: its metadata was never found, so a link
              // naming it points the recipient at nothing. The two dropdown
              // menus gate this the same way.
              (item is FolderDataTableItem && !item.isGhostFolder))
            PublicationMode.isOn
                // On a publication, the publication's own link to the item.
                ? _buildActionIcon(
                    tooltip: appLocalizationsOf(context).copyLink,
                    icon: ArDriveIcons.copy(size: defaultIconSize),
                    onTap: () => switch (item) {
                      FileDataTableItem(:final parentFolderId, :final id) =>
                        copyPublicationLink(
                          context,
                          folderId: parentFolderId,
                          fileId: id,
                        ),
                      FolderDataTableItem(:final id) =>
                        copyPublicationLink(context, folderId: id),
                      _ => copyPublicationLink(
                          context,
                          folderId: drive.rootFolderId,
                        ),
                    },
                  )
                : _buildActionIcon(
                    tooltip: _getShareTooltip(item, context),
                    icon: ArDriveIcons.share(size: defaultIconSize),
                    onTap: () {
                      if (item is FileDataTableItem) {
                        promptToShareFile(
                          context: context,
                          driveId: item.driveId,
                          fileId: item.id,
                        );
                      } else if (item is FolderDataTableItem) {
                        // A folder link is a drive link that names a folder, and it
                        // carries the drive key for the same reason - a folder in a
                        // private drive cannot be read without it.
                        promptToShareDrive(
                          context: context,
                          drive: drive,
                          folderId: item.id,
                          folderName: item.name,
                        );
                      } else if (item is DriveDataItem) {
                        promptToShareDrive(
                          context: context,
                          drive: drive,
                        );
                      }
                    },
                  ),
          // Publishing a folder or the drive; a file is shared, not published.
          if (item is! FileDataTableItem &&
              !(item is FolderDataTableItem && item.isGhostFolder) &&
              offersPublishToWeb(context, drive))
            _buildActionIcon(
              tooltip: publishToWebLabel(
                context,
                drive,
                item is FolderDataTableItem ? item.id : null,
              ),
              icon: publishToWebIcon(size: defaultIconSize),
              onTap: () => openPublishToWeb(
                context,
                drive: drive,
                folderId: item is FolderDataTableItem ? item.id : null,
              ),
            ),
          // A drive whose contents this device does not know has nothing to
          // download. Said by the details below it. See [offersDownload].
          if (offersDownload(item, context.watch<FsEntryInfoCubit>().state))
            _buildActionIcon(
                tooltip: appLocalizationsOf(context).download,
                icon: ArDriveIcons.download(size: defaultIconSize),
                onTap: () {
                  if (item is FileDataTableItem) {
                    promptToDownloadProfileFile(
                      context: context,
                      file: item,
                    );
                  } else if (item is FolderDataTableItem) {
                    promptToDownloadMultipleFiles(context,
                        selectedItems: [item], zipName: item.name);
                  } else if (item is DriveDataItem) {
                    promptToDownloadMultipleFiles(context,
                        selectedItems: [item], zipName: item.name);
                  }
                }),
          if (item is FileDataTableItem && drive.isPublic)
            _buildActionIcon(
              tooltip: appLocalizationsOf(context).preview,
              icon: ArDriveIcons.newWindow(size: defaultIconSize),
              onTap: () {
                final bloc = context.read<DriveDetailCubit>();
                bloc.launchPreview(item.dataTxId);
              },
            ),
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
          if (item.isOwner)
            _buildActionIcon(
              tooltip: item.isHidden
                  ? appLocalizationsOf(context).unhide
                  : appLocalizationsOf(context).hide,
              icon: item.isHidden
                  ? ArDriveIcons.eyeClosed(size: defaultIconSize)
                  : ArDriveIcons.eyeOpen(size: defaultIconSize),
              onTap: () {
                promptToToggleHideState(
                  context,
                  item: item,
                );
              },
            ),
          // Note: Sync/Deep Sync/Snapshot actions are in the drive kebab menu
          // to avoid redundant UI elements
          const Spacer(),
          _buildActionIcon(
            tooltip: appLocalizationsOf(context).close,
            icon: ArDriveIcons.x(size: defaultIconSize),
            onTap: onClose,
          ),
        ],
      ),
    );
  }

  String _getShareTooltip(ArDriveDataTableItem item, BuildContext context) {
    if (item is FileDataTableItem) {
      return appLocalizationsOf(context).shareFile;
    } else if (item is FolderDataTableItem) {
      return appLocalizationsOf(context).shareFolder;
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

class LicenseDetailsPopoverButton extends StatefulWidget {
  final LicenseState licenseState;
  final FileDataTableItem fileItem;
  final bool updateButton;
  final Aligned anchor;

  const LicenseDetailsPopoverButton({
    super.key,
    required this.licenseState,
    required this.fileItem,
    required this.updateButton,
    required this.anchor,
  });

  @override
  State<LicenseDetailsPopoverButton> createState() =>
      _LicenseDetailsPopoverButtonState();
}

class _LicenseDetailsPopoverButtonState
    extends State<LicenseDetailsPopoverButton> {
  bool _showLicenseDetailsCard = false;

  @override
  Widget build(BuildContext context) {
    return ArDriveOverlay(
      onVisibleChange: (visible) {
        if (!visible) {
          setState(() {
            _showLicenseDetailsCard = false;
          });
        }
      },
      visible: _showLicenseDetailsCard,
      anchor: widget.anchor,
      content: LicenseDetailsPopover(
        licenseState: widget.licenseState,
        closePopover: () {
          setState(() {
            _showLicenseDetailsCard = false;
          });
        },
        child: widget.updateButton
            ? ArDriveButtonNew(
                text:
                    // TODO: Localize
                    // appLocalizationsOf(context).licenseUpdate
                    'Update',
                typography: ArDriveTypographyNew.of(context),
                size: ArDriveButtonSize.compact,
                onPressed: () {
                  setState(() {
                    _showLicenseDetailsCard = false;
                  });
                  promptToLicense(
                    context,
                    driveId: widget.fileItem.driveId,
                    selectedItems: [widget.fileItem],
                  );
                },
              )
            : null,
      ),
      child: HoverWidget(
        hoverScale: 1.0,
        tooltip:
            // TODO: Localize
            // appLocalizations.of(context).licenseDetails,
            'View license details',
        child: ArDriveLink(
          text: widget.licenseState.meta.shortName,
          isAction: true,
          onTap: () {
            setState(() {
              _showLicenseDetailsCard = !_showLicenseDetailsCard;
            });
          },
        ),
      ),
    );
  }
}

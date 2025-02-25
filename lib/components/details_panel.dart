import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/arns/presentation/ant_icon.dart';
import 'package:ardrive/arns/presentation/assign_name_modal.dart';
import 'package:ardrive/arns/presentation/verify_name_bloc/verify_name_bloc.dart';
import 'package:ardrive/arns/utils/arns_address_utils.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/app_version_widget.dart';
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
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/is_supported_image_type_for_preview.dart';
import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../blocs/blocs.dart';
import '../utils/file_revision_base.dart';

class DetailsPanel extends StatefulWidget {
  const DetailsPanel({
    super.key,
    required this.item,
    required this.drivePrivacy,
    this.revisions,
    this.licenseState,
    this.fileKey,
    required this.isSharePage,
    this.currentDrive,
    this.onPreviousImageNavigation,
    this.onNextImageNavigation,
    required this.canNavigateThroughImages,
  });

  final ArDriveDataTableItem item;
  final Privacy drivePrivacy;
  final List<FileRevision>? revisions;
  final LicenseState? licenseState;
  final SecretKey? fileKey;
  final bool isSharePage;
  final Drive? currentDrive;
  final Function()? onPreviousImageNavigation;
  final Function()? onNextImageNavigation;
  final bool canNavigateThroughImages;

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
            isSharedFile: widget.isSharePage,
            maybeRevisions: widget.revisions,
            maybeLicenseState: widget.licenseState,
            driveDao: context.read<DriveDao>(),
            licenseService: context.read<LicenseService>(),
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
          builder: (context, infoState) {
            return ScreenTypeLayout.builder(
              desktop: (context) => Row(
                children: _buildContent(
                  mobileView: false,
                  previewState: previewState,
                  infoState: infoState,
                  context: context,
                ),
              ),
              mobile: (context) => Column(
                children: _buildContent(
                  mobileView: true,
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
    required bool mobileView,
    required FsEntryPreviewState previewState,
    required FsEntryInfoState infoState,
    required BuildContext context,
  }) {
    final isNotSharePageInMobileView = !(widget.isSharePage && !mobileView);
    final isPreviewUnavailable = previewState is FsEntryPreviewUnavailable;
    final isSharePage = widget.isSharePage;
    final typography = ArDriveTypographyNew.of(context);

    final tabs = [
      if (isNotSharePageInMobileView && !isPreviewUnavailable)
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
          ),
          child: BlocBuilder<FsEntryActivityCubit, FsEntryActivityState>(
            builder: (context, state) {
              return _buildActivity(state);
            },
          ),
        ),
      )
    ];

    return [
      if (isSharePage && !mobileView) ...[
        Flexible(
          flex: 2,
          child: Column(
            children: [
              Expanded(
                child: ArDriveCard(
                  borderRadius:
                      AppPlatform.isMobile || AppPlatform.isMobileWeb()
                          ? 0
                          : null,
                  backgroundColor: mobileView
                      ? ArDriveTheme.of(context)
                          .themeData
                          .tableTheme
                          .backgroundColor
                      : ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeBgSurface,
                  contentPadding: isSharePage
                      ? const EdgeInsets.only()
                      : const EdgeInsets.all(24),
                  content: _buildPreview(previewState, context: context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(
          height: 16,
          width: 16,
        ),
      ],
      Flexible(
        flex: 1,
        child: ArDriveCard(
          borderRadius:
              AppPlatform.isMobile || AppPlatform.isMobileWeb() ? 0 : null,
          backgroundColor: isSharePage
              ? ArDriveTheme.of(context).themeData.tableTheme.cellColor
              : ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            children: [
              if (!isSharePage)
                ScreenTypeLayout.builder(
                  desktop: (context) => Column(
                    children: [
                      BlocBuilder<DriveDetailCubit, DriveDetailState>(
                        builder: (context, driveDetailState) {
                          final driveDetailLoadSuccess =
                              driveDetailState as DriveDetailLoadSuccess;
                          return DetailsPanelToolbar(
                            item: widget.item,
                            driveDetailLoadSuccess: driveDetailLoadSuccess,
                          );
                        },
                      ),
                      const SizedBox(
                        height: 24,
                      ),
                    ],
                  ),
                  mobile: (context) => const SizedBox.shrink(),
                ),
              if (isSharePage && (!isPreviewUnavailable || mobileView))
                SizedBox(
                  height: 64,
                  child: Column(
                    children: [
                      ArDriveImage(
                        image: AssetImage(
                          // TODO: replace with ArDriveTheme .isLight method
                          ArDriveTheme.of(context).themeData.name == 'light'
                              ? Resources.images.brand.blackLogo2
                              : Resources.images.brand.whiteLogo2,
                        ),
                        height: 48,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
              if (!isSharePage ||
                  (isSharePage && isPreviewUnavailable && !mobileView))
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
                              null) ...{
                        const PinIndicator(
                          size: 32,
                        ),
                      },
                      if (widget.item is FileDataTableItem &&
                          (widget.item as FileDataTableItem).assignedNames !=
                              null &&
                          (widget.item as FileDataTableItem)
                              .assignedNames!
                              .isNotEmpty) ...{
                        AntIcon(
                          fileDataTableItem: widget.item as FileDataTableItem,
                        ),
                      },
                      if (widget.item is FileDataTableItem &&
                          isSupportedImageTypeForPreview(
                              widget.item.contentType) &&
                          (widget.item as FileDataTableItem).thumbnail ==
                              null &&
                          widget.item.isOwner) ...{
                        ArDriveIconButton(
                          icon: ArDriveIcons.image(),
                          tooltip: 'Create Thumbnail',
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
                      },
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
                child: Column(
                  children: [
                    Expanded(
                      child: ArDriveTabView(
                        key: Key(widget.item.id + tabs.length.toString()),
                        tabs: tabs,
                        backgroundColor: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeBgSurface,
                        unselectedTabColor: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeBgSurface,
                        unselectedLabelColor: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                    ),
                    if (isSharePage && (!isPreviewUnavailable || mobileView))
                      SizedBox(
                        height: 138,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            SizedBox(
                              height: 40,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ArDriveButton(
                                      icon: ArDriveIcons.download(
                                          color: Colors.white),
                                      onPressed: () {
                                        final file = ARFSFactory()
                                            .getARFSFileFromFileRevision(
                                          widget.revisions!.last,
                                        );
                                        return promptToDownloadSharedFile(
                                          revision: file,
                                          context: context,
                                          fileKey: widget.fileKey,
                                        );
                                      },
                                      text:
                                          appLocalizationsOf(context).download,
                                    ),
                                  )
                                ],
                              ),
                            ),
                            ArDriveButton(
                              style: ArDriveButtonStyle.tertiary,
                              onPressed: () =>
                                  openUrl(url: Resources.ardrivePublicSiteLink),
                              text: appLocalizationsOf(context).whatIsArDrive,
                            ),
                            if (widget.isSharePage) ...[
                              AppVersionWidget(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgDefault,
                              ),
                            ]
                          ],
                        ),
                      ),
                  ],
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
    if (previewState is FsEntryPreviewUnavailable && widget.isSharePage) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 400,
            minWidth: kMediumDialogWidth,
            minHeight: 256,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ArDriveImage(
                image: AssetImage(
                  ArDriveTheme.of(context).themeData.name == 'light'
                      ? Resources.images.brand.blackLogo2
                      : Resources.images.brand.whiteLogo2,
                ),
                height: 80,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              IntrinsicWidth(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: DriveExplorerItemTileLeading(item: widget.item),
                  title: ArDriveTooltip(
                    message: widget.item.name,
                    child: Text(
                      widget.item.name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: ArDriveTypography.body.buttonLargeBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                    ),
                  ),
                  subtitle: Text(
                    filesize(widget.item.size),
                    style: ArDriveTypography.body.buttonNormalRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeAccentDisabled,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ArDriveButton(
                icon: ArDriveIcons.download(color: Colors.white),
                onPressed: () {
                  final file = ARFSFactory().getARFSFileFromFileRevision(
                    widget.revisions!.last,
                  );
                  return promptToDownloadSharedFile(
                    revision: file,
                    context: context,
                    fileKey: widget.fileKey,
                  );
                },
                text: appLocalizationsOf(context).download,
              ),
              const SizedBox(height: 16),
              ArDriveButton(
                style: ArDriveButtonStyle.tertiary,
                onPressed: () => openUrl(url: Resources.ardrivePublicSiteLink),
                text: appLocalizationsOf(context).whatIsArDrive,
              ),
              if (widget.isSharePage) ...[
                AppVersionWidget(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                ),
              ]
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.center,
      child: FsEntryPreviewWidget(
        key: ValueKey(widget.item.id),
        state: previewState,
        isSharePage: widget.isSharePage,
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
    } else if (state is FsEntryFileInfoSuccess || widget.revisions != null) {
      children = _fileDetails(state);
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
          style: typography.paragraphNormal(),
        ),
        itemTitle: appLocalizationsOf(context).itemContains,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateToUtcString(widget.item.lastUpdated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateToUtcString(widget.item.dateCreated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
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
            _TxIdTextLink(txId: folder.metadataTxId),
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
    final typography = ArDriveTypographyNew.of(context);

    return [
      DetailsPanelItem(
        leading: CopyButton(text: widget.item.id),
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
          formatDateToUtcString(widget.item.lastUpdated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateToUtcString(widget.item.dateCreated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).dateCreated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TxIdTextLink(txId: state.metadataTxId),
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

  List<Widget> _fileDetails(FsEntryInfoState state) {
    final item = widget.item as FileDataTableItem;
    String? pinnedDataOwnerAddress = item.pinnedDataOwnerAddress;

    final typography = ArDriveTypographyNew.of(context);

    return [
      DetailsPanelItem(
        leading: CopyButton(text: item.id),
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
          formatDateToUtcString(item.lastUpdated),
          style: typography.paragraphNormal(),
          textAlign: TextAlign.right,
        ),
        itemTitle: appLocalizationsOf(context).lastUpdated,
      ),
      sizedBoxHeight16px,
      DetailsPanelItem(
        leading: Text(
          formatDateToUtcString(item.dateCreated),
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
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TxIdTextLink(txId: item.dataTxId),
            const SizedBox(width: 12),
            CopyButton(
              text: item.dataTxId,
            ),
          ],
        ),
        itemTitle: appLocalizationsOf(context).dataTxID,
      ),
      sizedBoxHeight16px,
      if (state is FsEntryInfoSuccess)
        DetailsPanelItem(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TxIdTextLink(txId: state.metadataTxId),
              const SizedBox(width: 12),
              CopyButton(
                text: state.metadataTxId,
              ),
            ],
          ),
          itemTitle: appLocalizationsOf(context).metadataTxID,
        ),
      sizedBoxHeight16px,
      if (item.fallbackTxId != null) ...[
        DetailsPanelItem(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TxIdTextLink(txId: item.fallbackTxId!),
              const SizedBox(width: 12),
              CopyButton(
                text: item.fallbackTxId!,
              ),
            ],
          ),
          itemTitle: 'Manifest Fallback TxID',
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
                      updateButton:
                          !widget.isSharePage && pinnedDataOwnerAddress == null,
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
                  : (!widget.isSharePage && pinnedDataOwnerAddress == null)
                      ? ArDriveButton(
                          text: 'Add',
                          icon: ArDriveIcons.license(
                            size: 16,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .backgroundColor,
                          ),
                          fontStyle: ArDriveTypography.body.buttonNormalBold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .backgroundColor,
                          ),
                          backgroundColor: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
                          maxHeight: 32,
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
      if (widget.drivePrivacy == DrivePrivacy.public.name) ...[
        sizedBoxHeight16px,
        DetailsPanelItem(
          leading: _ArnsNameDisplay(fileItem: item),
          itemTitle: 'ArNS Name',
        ),
      ],
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
            null,
            revision.action,
            widget.fileKey,
            fileRevision: revision,
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
                case RevisionAction.hide:
                  title = appLocalizationsOf(context).folderWasHidden;
                  break;
                case RevisionAction.unhide:
                  title = appLocalizationsOf(context).folderWasUnhidden;
                  break;
                default:
                  title = appLocalizationsOf(context).folderWasModified;
              }
              subtitle = formatDateToUtcString(revision.dateCreated);

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
                null,
                fileRevisionWithLicenseAndTransactions: revision,
              );
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
                case RevisionAction.hide:
                  title = appLocalizationsOf(context).driveWasHidden;
                  break;
                case RevisionAction.unhide:
                  title = appLocalizationsOf(context).driveWasUnhidden;
                  break;
                default:
                  title = appLocalizationsOf(context).driveWasModified;
              }

              subtitle = formatDateToUtcString(revision.dateCreated);

              return DetailsPanelItem(
                itemSubtitle: subtitle,
                itemTitle: title,
                expandLeading: false,
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
    LicenseState? licenseState,
    String action,
    SecretKey? key, {
    FileRevision? fileRevision,
    FileRevisionWithLicenseAndTransactions?
        fileRevisionWithLicenseAndTransactions,
  }) {
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

        if (fileRevision != null) {
          leading = _FileRevisionOptions(
            fileRevision: FileRevisionBase.fromFileRevision(fileRevision),
          );
        }

        if (fileRevisionWithLicenseAndTransactions != null) {
          leading = _FileRevisionOptions(
            fileRevision: FileRevisionBase.fromFileRevisionWithLicense(
                fileRevisionWithLicenseAndTransactions),
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
        title = appLocalizationsOf(context).fileHadANewRevision;
        leading = _DownloadOrPreview(
          isSharedFile: widget.isSharePage,
          privacy: widget.drivePrivacy,
          fileRevision: file,
          fileKey: key,
        );

        if (fileRevision != null) {
          leading = _FileRevisionOptions(
            fileRevision: FileRevisionBase.fromFileRevision(fileRevision),
          );
        }

        if (fileRevisionWithLicenseAndTransactions != null) {
          leading = _FileRevisionOptions(
            fileRevision: FileRevisionBase.fromFileRevisionWithLicense(
                fileRevisionWithLicenseAndTransactions),
          );
        }

        break;
      case RevisionAction.assignName:
        title = 'File had name assigned ${file.assignedNames?.last}';
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
      default:
        title = appLocalizationsOf(context).fileWasModified;
    }
    subtitle = formatDateToUtcString(file.unixTime);

    return DetailsPanelItem(
      leading: leading ?? const SizedBox(),
      itemTitle: title,
      itemSubtitle: subtitle,
      expandLeading: false,
    );
  }
}

class _TxIdTextLink extends StatelessWidget {
  const _TxIdTextLink({required this.txId});

  final String txId;

  @override
  Widget build(BuildContext context) {
    return ArDriveClickArea(
      child: GestureDetector(
        onTap: () {
          openUrl(url: 'https://viewblock.io/arweave/tx/$txId');
        },
        child: ArDriveTooltip(
          message: txId,
          child: Text(
            '${txId.substring(0, 4)}...',
            style: ArDriveTypography.body
                .buttonNormalRegular()
                .copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ),
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
                      itemTitle,
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
                        style: ArDriveTypography.body.xSmallRegular(),
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
    super.key,
    required this.text,
    this.size = 20,
    this.showCopyText = true,
    this.child,
    this.positionY = 40,
    this.positionX = 20,
    this.copyMessageColor,
  });

  @override
  // ignore: library_private_types_in_public_api
  _CopyButtonState createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _showCheck = false;
  OverlayEntry? _overlayEntry;

  @override
  dispose() {
    if (_overlayEntry != null && _overlayEntry!.mounted) {
      _overlayEntry?.remove();
    }
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
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return OverlayEntry(
      builder: (context) => Positioned(
        left: buttonPosition.dx - widget.positionX,
        top: buttonPosition.dy - widget.positionY,
        child: Material(
          color: widget.copyMessageColor ?? colorTokens.containerL1,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Center(
              child: Text(
                'Copied!',
                style: typography.paragraphNormal(),
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
    required this.privacy,
    required this.fileRevision,
    this.fileKey,
    this.isSharedFile = false,
  });

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

class _FileRevisionOptions extends StatelessWidget {
  const _FileRevisionOptions({
    required this.fileRevision,
  });

  final FileRevisionBase fileRevision;

  @override
  Widget build(BuildContext context) {
    final item = DriveDataTableItemMapper.fromRevision(fileRevision, true);

    return EntityActionsMenu(
      item: item,
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
    required this.driveDetailLoadSuccess,
  });

  final ArDriveDataTableItem item;
  final DriveDetailLoadSuccess driveDetailLoadSuccess;

  @override
  Widget build(BuildContext context) {
    final drive = driveDetailLoadSuccess.currentDrive;

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
          _buildActionIcon(
              tooltip: appLocalizationsOf(context).download,
              icon: ArDriveIcons.download(size: defaultIconSize),
              onTap: () {
                if (item is FileDataTableItem) {
                  promptToDownloadProfileFile(
                    context: context,
                    file: item as FileDataTableItem,
                  );
                } else if (item is FolderDataTableItem) {
                  promptToDownloadMultipleFiles(context,
                      selectedItems: [item as FolderDataTableItem],
                      zipName: item.name);
                } else if (item is DriveDataItem) {
                  promptToDownloadMultipleFiles(context,
                      selectedItems: [item as DriveDataItem],
                      zipName: item.name);
                }
              }),
          if (item is FileDataTableItem && drive.isPublic)
            _buildActionIcon(
              tooltip: appLocalizationsOf(context).preview,
              icon: ArDriveIcons.newWindow(size: defaultIconSize),
              onTap: () {
                final bloc = context.read<DriveDetailCubit>();
                bloc.launchPreview((item as FileDataTableItem).dataTxId);
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
            ? ArDriveButton(
                text:
                    // TODO: Localize
                    // appLocalizationsOf(context).licenseUpdate
                    'Update',
                icon: ArDriveIcons.license(
                  size: 16,
                  color: ArDriveTheme.of(context).themeData.backgroundColor,
                ),
                fontStyle: ArDriveTypography.body.buttonNormalBold(
                  color: ArDriveTheme.of(context).themeData.backgroundColor,
                ),
                backgroundColor:
                    ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                maxHeight: 32,
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
        child: ArDriveButton(
          text: widget.licenseState.meta.shortName,
          style: ArDriveButtonStyle.tertiary,
          onPressed: () {
            setState(() {
              _showLicenseDetailsCard = !_showLicenseDetailsCard;
            });
          },
        ),
      ),
    );
  }
}

class _ArnsNameDisplay extends StatelessWidget {
  final FileDataTableItem fileItem;

  const _ArnsNameDisplay({required this.fileItem});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => VerifyNameBloc(
        arnsRepository: context.read<ARNSRepository>(),
      )..add(VerifyName(fileId: fileItem.fileId)),
      child: BlocBuilder<VerifyNameBloc, VerifyNameState>(
        builder: (context, state) {
          final typography = ArDriveTypographyNew.of(context);

          if (state is VerifyNameLoading || state is VerifyNameInitial) {
            return const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            );
          }

          if (state is VerifyNameEmpty || state is VerifyNameFailure) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArDriveButton(
                  text: 'Assign',
                  icon: ArDriveIcons.arnsName(
                    size: 16,
                    color: ArDriveTheme.of(context).themeData.backgroundColor,
                  ),
                  fontStyle: ArDriveTypography.body.buttonNormalBold(
                    color: ArDriveTheme.of(context).themeData.backgroundColor,
                  ),
                  backgroundColor:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                  maxHeight: 32,
                  onPressed: () {
                    showAssignArNSNameModal(
                      context,
                      file: fileItem,
                      driveDetailCubit: context.read<DriveDetailCubit>(),
                    ).then((_) {
                      // Refresh both the verify name bloc and the file info cubit
                      context
                          .read<VerifyNameBloc>()
                          .add(VerifyName(fileId: fileItem.fileId));
                      context.read<DriveDetailCubit>().refreshDriveDataTable();
                    });
                  },
                ),
              ],
            );
          }

          if (state is VerifyNameSuccess) {
            final (address, arAddress) = getAddressesFromArns(
              domain: state.undername.domain,
              undername: state.undername.name,
            );

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ArDriveClickArea(
                    child: GestureDetector(
                      onTap: () => openUrl(url: address),
                      child: ArDriveTooltip(
                        message: arAddress,
                        child: Text(
                          getLiteralARNSRecordName(
                            ARNSUndernameFactory.create(
                              name: state.undername.name,
                              domain: state.undername.domain,
                              transactionId: state.undername.transactionId,
                            ),
                          ),
                          style: typography.paragraphNormal().copyWith(
                                decoration: TextDecoration.underline,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                CopyButton(
                  text: arAddress,
                ),
              ],
            );
          }

          return const SizedBox();
        },
      ),
    );
  }
}

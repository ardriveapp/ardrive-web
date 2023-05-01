import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/drive_share_dialog.dart';
import 'package:ardrive/components/fs_entry_move_form.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/drive_explorer/provider/drive_explorer_provider.dart';
import 'package:ardrive/drive_explorer/provider/drives_provider.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/drive_file_drop_zone.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:responsive_builder/responsive_builder.dart';

class ArDriveExplorerPageProvider extends StatefulWidget {
  const ArDriveExplorerPageProvider({
    Key? key,
    required this.drive,
  }) : super(key: key);

  final Drive drive;

  @override
  State<ArDriveExplorerPageProvider> createState() =>
      _ArDriveExplorerPageProviderState();
}

class _ArDriveExplorerPageProviderState
    extends State<ArDriveExplorerPageProvider> {
  @override
  void initState() {
    super.initState();
    context.read<DrivesProvider>().loadDrives();
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DrivesProvider>().currentDrive;

    if (drive == null) {
      return const SizedBox.shrink();
    }

    logger.d('ArDriveExplorerPage build');

    logger.d('current drive: ${drive.name}');

    return ChangeNotifierProvider(
      create: (_) => DriveExplorerProvider(
        appActivity: context.read<AppActivity>(),
        syncCubit: context.read<SyncCubit>(),
        drive: drive,
        // arfsRepository: context.read<SyncCubit>().arfsRepository,
        driveDao: context.read<DriveDao>(),
        auth: context.read<ArDriveAuth>(),
      ),
      child: const _ArDriveExplorerPage(),
    );
  }
}

class _ArDriveExplorerPage extends StatefulWidget {
  const _ArDriveExplorerPage();

  @override
  State<_ArDriveExplorerPage> createState() => _ArDriveExplorerPageState();
}

class _ArDriveExplorerPageState extends State<_ArDriveExplorerPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScreenTypeLayout(
        desktop: Row(
          children: [
            const AppSideBar(),
            Consumer<DrivesProvider>(
              builder: (context, drivesProvider, _) {
                final drive = drivesProvider.currentDrive;

                if (drive?.id !=
                    context.read<DriveExplorerProvider>().drive.id) {
                  context.read<DriveExplorerProvider>().openDriveRoot(drive!);
                }

                return Consumer<DriveExplorerProvider>(
                  builder: (context, provider, __) {
                    final drive = provider.drive;
                    final driveExplorer = provider.driveExplorer;
                    if (driveExplorer == null) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    final isOwner = isDriveOwner(
                        context.read<ArDriveAuth>(), drive.ownerAddress);

                    final canDownloadMultipleFiles = context
                            .read<DriveExplorerProvider>()
                            .isMultiSelectMode &&
                        drive.privacy == 'public' &&
                        !provider.selectedItems
                            .any((element) => element is FolderDataTableItem);

                    return Expanded(
                      child: _desktopView(
                        drive: drive,
                        folder: driveExplorer.folderInView,
                        isDriveOwner: isOwner,
                        // TODO
                        // hasSubfolders: hasSubfolders,
                        // hasFiles: hasFiles,
                        hasFiles: true,
                        hasSubfolders: true,
                        canDownloadMultipleFiles: canDownloadMultipleFiles,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
        mobile: SizedBox.shrink(),
        // TODO
        // mobile: Scaffold(
        //   drawer: const AppSideBar(),
        //   appBar: (state.showSelectedItemDetails &&
        //           context.read<DriveDetailCubit>().selectedItem != null)
        //       ? MobileAppBar(
        //           leading: ArDriveIconButton(
        //             icon: ArDriveIcons.arrowLeft(),
        //             onPressed: () {
        //               context
        //                   .read<DriveDetailCubit>()
        //                   .toggleSelectedItemDetails();
        //             },
        //           ),
        //         )
        //       : null,
        // body: _mobileView(
        //   state,
        //   hasSubfolders,
        //   hasFiles,
        //   state.currentFolderContents,
        // )
        // ,
        // ),
      ),
    );
  }

  Widget _desktopView({
    required Drive drive,
    required FolderDataTableItem folder,
    required bool hasSubfolders,
    required bool hasFiles,
    required bool isDriveOwner,
    required bool canDownloadMultipleFiles,
  }) {
    logger.d('folder path ${folder.path}');
    return Column(
      children: [
        const AppTopBar(),
        Expanded(
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ArDriveCard(
                            backgroundColor: ArDriveTheme.of(context)
                                .themeData
                                .tableTheme
                                .backgroundColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            content: Row(
                              children: [
                                DriveDetailBreadcrumbRow(
                                  path: folder.path,
                                  driveName: drive.name,
                                ),
                                const Spacer(),
                                // TODO
                                // if (state.multiselect && isDriveOwner)
                                ArDriveIconButton(
                                  tooltip: appLocalizationsOf(context).move,
                                  icon: ArDriveIcons.move(),
                                  onPressed: () {
                                    promptToMove(
                                      context,
                                      driveId: drive.id,
                                      selectedItems: context
                                          .read<DriveExplorerProvider>()
                                          .selectedItems,
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                if (canDownloadMultipleFiles &&
                                    context
                                        .read<AppConfig>()
                                        .enableMultipleFileDownload) ...[
                                  ArDriveIconButton(
                                    tooltip: 'Download selected files',
                                    icon: ArDriveIcons.download(),
                                    onPressed: () {
                                      // final files = context
                                      //     .read<DriveDetailCubit>()
                                      //     .selectedItems
                                      //     .whereType<FileDataTableItem>()
                                      //     .toList();

                                      // promptToDownloadMultipleFiles(
                                      //   context,
                                      //   items: files,
                                      // );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                // TODO
                                if (context
                                    .read<DriveExplorerProvider>()
                                    .isMultiSelectMode)
                                  if (context
                                      .read<DriveExplorerProvider>()
                                      .isMultiSelectMode)
                                    const SizedBox(
                                      height: 24,
                                      child: VerticalDivider(),
                                    ),
                                ArDriveClickArea(
                                  tooltip: appLocalizationsOf(context).showMenu,
                                  child: ArDriveDropdown(
                                    width: 260,
                                    anchor: const Aligned(
                                      follower: Alignment.topRight,
                                      target: Alignment.bottomRight,
                                    ),
                                    items: [
                                      if (isDriveOwner)
                                        ArDriveDropdownItem(
                                          onClick: () {
                                            promptToRenameDrive(
                                              context,
                                              driveId: drive.id,
                                              driveName: drive.name,
                                            );
                                          },
                                          content: ArDriveDropdownItemTile(
                                            name: appLocalizationsOf(context)
                                                .renameDrive,
                                            icon: ArDriveIcons.edit(
                                              size: defaultIconSize,
                                            ),
                                          ),
                                        ),
                                      ArDriveDropdownItem(
                                        onClick: () {
                                          promptToShareDrive(
                                            context: context,
                                            drive: drive,
                                          );
                                        },
                                        content: ArDriveDropdownItemTile(
                                          name: appLocalizationsOf(context)
                                              .shareDrive,
                                          icon: ArDriveIcons.share(
                                            size: defaultIconSize,
                                          ),
                                        ),
                                      ),
                                      ArDriveDropdownItem(
                                        onClick: () {
                                          promptToExportCSVData(
                                            context: context,
                                            driveId: drive.id,
                                          );
                                        },
                                        content: ArDriveDropdownItemTile(
                                          name: appLocalizationsOf(context)
                                              .exportDriveContents,
                                          icon: ArDriveIcons.download(
                                            size: defaultIconSize,
                                          ),
                                        ),
                                      ),
                                      ArDriveDropdownItem(
                                        onClick: () {
                                          // final bloc =
                                          //     context.read<DriveDetailCubit>();

                                          // bloc.selectDataItem(
                                          //   DriveDataTableItemMapper.fromDrive(
                                          //     state.currentDrive,
                                          //     (_) => null,
                                          //     0,
                                          //     isDriveOwner,
                                          //   ),
                                          // );
                                        },
                                        content: _buildItem(
                                          appLocalizationsOf(context).moreInfo,
                                          ArDriveIcons.info(
                                            size: defaultIconSize,
                                          ),
                                        ),
                                      )
                                    ],
                                    child: HoverWidget(
                                      child: ArDriveIcons.kebabMenu(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(
                            height: 30,
                          ),
                          if (hasFiles || hasSubfolders)
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildDataListContent(
                                      drive: drive,
                                      folder: folder,
                                      context: context,
                                      isDriveOwner: isDriveOwner,
                                      items: context
                                          .watch<DriveExplorerProvider>()
                                          .driveExplorer!
                                          .items,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Expanded(
                              child: DriveDetailFolderEmptyCard(
                                driveId: drive.id,
                                parentFolderId: folder.id,
                                // TODO
                                // promptToAddFiles: state.hasWritePermissions,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // TODO
                  Selector<DriveExplorerProvider, ArDriveDataTableItem?>(
                      selector: (_, provider) => provider.selectedItem,
                      builder: (context, item, _) {
                        return AnimatedSize(
                          curve: Curves.easeInOut,
                          duration: const Duration(milliseconds: 300),
                          child: Align(
                            alignment: Alignment.center,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: 400,
                                minWidth: 0,
                              ),
                              child: item != null
                                  ? DetailsPanel(
                                      isSharePage: false,
                                      drivePrivacy: drive.privacy,
                                      maybeSelectedItem: null,
                                      item: item,
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                        );
                      })
                ],
              ),
              if (kIsWeb)
                DriveFileDropZone(
                  driveId: drive.id,
                  folderId: folder.id,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // TODO
  double _getMaxWidthForDetailsPanel(BuildContext context) {
    // if (state.showSelectedItemDetails &&
    //     context.read<DriveDetailCubit>().selectedItem != null) {
    // if (MediaQuery.of(context).size.width * 0.25 < 375) {
    return 375;
    // }
    // return MediaQuery.of(context).size.width * 0.25;
    // }
    // return 0;
  }

  // TODO
  double _getMinWidthForDetailsPanel(BuildContext context) {
    // if (state.showSelectedItemDetails &&
    //     context.read<DriveDetailCubit>().selectedItem != null) {
    return 375;
    // }
    // return 0;
  }

  _buildItem(String name, ArDriveIcon icon) {
    return ArDriveDropdownItemTile(
      name: name,
      icon: icon,
    );
  }

  ArDriveDataTable _buildDataListContent({
    required BuildContext context,
    required Drive drive,
    required FolderDataTableItem folder,
    required bool isDriveOwner,
    required List<ArDriveDataTableItem> items,
  }) {
    return ArDriveDataTable<ArDriveDataTableItem>(
      key: ValueKey(folder.id),
      lockMultiSelect: context.watch<SyncCubit>().state is SyncInProgress,
      rowsPerPageText: appLocalizationsOf(context).rowsPerPage,
      maxItemsPerPage: 100,
      pageItemsDivisorFactor: 25,
      onSelectedRows: (boxes) {
        final provider = context.read<DriveExplorerProvider>();

        if (boxes.isEmpty) {
          provider.isMultiSelectMode = false;
          return;
        }

        final multiSelectedItems = boxes
            .map((e) => e.selectedItems.map((e) => e))
            .expand((e) => e)
            .toList();

        provider.selectItems(multiSelectedItems);
      },
      onChangeMultiSelecting: (isMultiselecting) {
        context.read<DriveExplorerProvider>().isMultiSelectMode =
            isMultiselecting;
      },
      forceDisableMultiSelect: false,
      // context.read<DriveDetailCubit>().forceDisableMultiselect,
      columns: [
        TableColumn(appLocalizationsOf(context).name, 2),
        TableColumn(appLocalizationsOf(context).size, 1),
        TableColumn(appLocalizationsOf(context).lastUpdated, 1),
        TableColumn(appLocalizationsOf(context).dateCreated, 1),
      ],
      trailing: (file) =>
          context.read<DriveExplorerProvider>().isMultiSelectMode
              ? const SizedBox.shrink()
              : DriveExplorerItemTileTrailing(
                  drive: drive,
                  item: file,
                ),
      leading: (file) => DriveExplorerItemTileLeading(
        item: file,
      ),
      onRowTap: (item) {
        if (item is FolderDataTableItem) {
          return context.read<DriveExplorerProvider>().openFolder(item.path);
        }

        return context.read<DriveExplorerProvider>().selectItem(item);
      },
      sortRows: (list, columnIndex, ascDescSort) {
        // Separate folders and files
        List<ArDriveDataTableItem> folders = [];
        List<ArDriveDataTableItem> files = [];

        final lenght = list.length;

        for (int i = 0; i < lenght; i++) {
          if (list[i] is FolderDataTableItem) {
            folders.add(list[i]);
          } else {
            files.add(list[i]);
          }
        }

        // Sort folders and files
        _sortFoldersAndFiles(folders, files, columnIndex, ascDescSort);

        return folders + files;
      },
      buildRow: (row) {
        return DriveExplorerItemTile(
          name: row.name,
          size: row.size == null ? '-' : filesize(row.size),
          lastUpdated: yMMdDateFormatter.format(row.lastUpdated),
          dateCreated: yMMdDateFormatter.format(row.dateCreated),
          onPressed: () => row.onPressed(row),
        );
      },
      rows: items,
    );
  }

  void _sortFoldersAndFiles(
      List<ArDriveDataTableItem> folders,
      List<ArDriveDataTableItem> files,
      int columnIndex,
      TableSort ascDescSort) {
    _sortItems(folders, columnIndex, ascDescSort);
    _sortItems(files, columnIndex, ascDescSort);
  }

  int _getResult(int result, TableSort ascDescSort) {
    if (ascDescSort == TableSort.asc) {
      result *= -1;
    }

    return result;
  }

  void _sortItems(List<ArDriveDataTableItem> items, int columnIndex,
      TableSort ascDescSort) {
    items.sort((a, b) {
      int result = 0;
      if (columnIndex == ColumnIndexes.name) {
        result = compareAlphabeticallyAndNatural(a.name, b.name);
      } else if (columnIndex == ColumnIndexes.size) {
        result = (a.size ?? 0).compareTo(b.size ?? 0);
      } else if (columnIndex == ColumnIndexes.lastUpdated) {
        result = a.lastUpdated.compareTo(b.lastUpdated);
      } else {
        result = a.dateCreated.compareTo(b.dateCreated);
      }
      return _getResult(result, ascDescSort);
    });
  }
}

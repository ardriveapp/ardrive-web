import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/utils/breadcrumb_builder.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

part 'drive_detail_state.dart';

class DriveDetailCubit extends Cubit<DriveDetailState> {
  String _driveId;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ConfigService _configService;
  final ArDriveAuth _auth;
  final ActivityTracker _activityTracker;
  final BreadcrumbBuilder _breadcrumbBuilder;
  final SyncCubit _syncCubit;

  final DriveRepository _driveRepository;

  StreamSubscription? _folderSubscription;
  final _defaultAvailableRowsPerPage = [25, 50, 75, 100];

  List<ArDriveDataTableItem> _selectedItems = [];
  List<ArDriveDataTableItem> get selectedItems => _selectedItems;

  List<FileDataTableItem>? _allImagesOfCurrentFolder;

  bool _forceDisableMultiselect = false;

  bool _refreshSelectedItem = false;

  DriveDetailCubit({
    required String driveId,
    String? initialFolderId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ConfigService configService,
    required ActivityTracker activityTracker,
    required ArDriveAuth auth,
    required BreadcrumbBuilder breadcrumbBuilder,
    required SyncCubit syncCubit,
    required DriveRepository driveRepository,
  })  : _profileCubit = profileCubit,
        _activityTracker = activityTracker,
        _driveDao = driveDao,
        _auth = auth,
        _configService = configService,
        _breadcrumbBuilder = breadcrumbBuilder,
        _syncCubit = syncCubit,
        _driveRepository = driveRepository,
        _driveId = driveId,
        super(DriveDetailLoadInProgress()) {
    if (driveId.isEmpty) {
      return;
    }

    if (initialFolderId != null) {
      // TODO: Handle deep-linking folders of unattached drives.
      Future.microtask(() async {
        final folder = await _driveDao
            .folderById(folderId: initialFolderId)
            .getSingleOrNull();
        // Open the root folder if the deep-linked folder could not be found.

        openFolder(folderId: folder?.id);
        // The empty string here is required to open the root folder
      });
    } else {
      Future.microtask(() async {
        final drive =
            await _driveDao.driveById(driveId: driveId).getSingleOrNull();
        openFolder(folderId: drive?.rootFolderId);
      });
    }
  }

  void showEmptyDriveDetail() async {
    await _syncCubit.waitCurrentSync();

    emit(DriveDetailLoadEmpty());
  }

  Future<void> changeDrive(String driveId) async {
    final drive = await _driveDao.driveById(driveId: driveId).getSingleOrNull();

    if (drive == null) {
      await _syncCubit.waitCurrentSync();
      emit(DriveDetailLoadNotFound());
      return;
    }

    await _folderSubscription?.cancel();

    _driveId = driveId;

    openFolder(folderId: drive.rootFolderId);
  }

  Future<void> openFolder({
    String? folderId,
    String? otherDriveId,
    String? selectedItemId,
    DriveOrder contentOrderBy = DriveOrder.name,
    OrderingMode contentOrderingMode = OrderingMode.asc,
  }) async {
    /// always wait for the current sync to finish before opening a new folder
    await _syncCubit.waitCurrentSync();

    try {
      _allImagesOfCurrentFolder = null;

      String driveId = otherDriveId ?? _driveId;

      emit(DriveDetailLoadInProgress());

      await _folderSubscription?.cancel();

      _folderSubscription =
          Rx.combineLatest3<Drive?, FolderWithContents, ProfileState, void>(
        _driveRepository.watchDrive(driveId: driveId),
        _driveDao
            .watchFolderContents(
          driveId,
          orderBy: contentOrderBy,
          orderingMode: contentOrderingMode,
          folderId: folderId,
        )
            .handleError((error, stack) {
          logger.e('Error watching folder contents', error, stack);
          if (error is DriveNotFoundException) {
            emit(DriveDetailLoadNotFound());
          }

          return null;
        }),
        _profileCubit.stream.startWith(ProfileCheckingAvailability()),
        (drive, folderContents, _) async {
          if (isClosed) {
            return;
          }

          if (driveId != _driveId) {
            return;
          }

          await _syncCubit.waitCurrentSync();

          if (drive == null) {
            emit(DriveDetailLoadNotFound());
            return;
          }

          if (_activityTracker.isUploading) {
            return;
          }

          final state = this.state is DriveDetailLoadSuccess
              ? this.state as DriveDetailLoadSuccess
              : null;

          final profile = _profileCubit.state;

          final availableRowsPerPage = calculateRowsPerPage(
            folderContents.files.length + folderContents.subfolders.length,
          );

          if (_selectedItem != null && _refreshSelectedItem) {
            if (_selectedItem is FileDataTableItem) {
              final index = folderContents.files.indexWhere(
                (element) => element.id == _selectedItem!.id,
              );

              if (index >= 0) {
                final item = folderContents.files[index];

                _selectedItem = DriveDataTableItemMapper.toFileDataTableItem(
                  item,
                  _selectedItem!.index,
                  _selectedItem!.isOwner,
                );
              }
            } else if (_selectedItem is FolderDataTableItem) {
              final index = folderContents.subfolders.indexWhere(
                (element) => element.id == _selectedItem!.id,
              );
              if (index >= 0) {
                final item = folderContents.subfolders[index];

                _selectedItem = DriveDataTableItemMapper.fromFolderEntry(
                  item,
                  _selectedItem!.index,
                  _selectedItem!.isOwner,
                );
              }
            } else {
              _selectedItem = DriveDataTableItemMapper.fromDrive(
                drive,
                (item) => null,
                0,
                _selectedItem!.isOwner,
              );
            }
          }

          final currentFolderContents = parseEntitiesToDatatableItem(
            folder: folderContents,
            isOwner: isDriveOwner(_auth, drive.ownerAddress),
          );

          if (selectedItemId != null) {
            _selectedItem = currentFolderContents.firstWhere(
              (element) => element.id == selectedItemId,
            );
          }

          final List<BreadCrumbRowInfo> pathSegments =
              await _breadcrumbBuilder.buildForFolder(
            folderId: folderContents.folder.id,
            rootFolderId: drive.rootFolderId,
            driveId: driveId,
          );

          if (state != null) {
            emit(
              state.copyWith(
                selectedItem: _selectedItem,
                currentDrive: drive,
                hasWritePermissions: profile is ProfileLoggedIn &&
                    drive.ownerAddress == profile.user.walletAddress,
                folderInView: folderContents,
                contentOrderBy: contentOrderBy,
                contentOrderingMode: contentOrderingMode,
                rowsPerPage: availableRowsPerPage.first,
                availableRowsPerPage: availableRowsPerPage,
                currentFolderContents: currentFolderContents,
                pathSegments: pathSegments,
                driveIsEmpty: folderContents.files.isEmpty &&
                    folderContents.subfolders.isEmpty,
                showSelectedItemDetails: _selectedItem != null,
              ),
            );
          } else {
            final columnsVisibility = await getTableColumnVisibility();

            emit(
              DriveDetailLoadSuccess(
                pathSegments: pathSegments,
                selectedItem: _selectedItem,
                currentDrive: drive,
                hasWritePermissions: profile is ProfileLoggedIn &&
                    drive.ownerAddress == profile.user.walletAddress,
                folderInView: folderContents,
                contentOrderBy: contentOrderBy,
                contentOrderingMode: contentOrderingMode,
                rowsPerPage: availableRowsPerPage.first,
                availableRowsPerPage: availableRowsPerPage,
                driveIsEmpty: folderContents.files.isEmpty &&
                    folderContents.subfolders.isEmpty,
                multiselect: false,
                currentFolderContents: currentFolderContents,
                columnVisibility: columnsVisibility,
                showSelectedItemDetails: _selectedItem != null,
              ),
            );
          }
        },
      ).listen((_) {});
    } catch (e, stacktrace) {
      logger.e('An error occured mouting the drive explorer', e, stacktrace);
    }

    _folderSubscription?.onError((e) {
      if (e is FolderNotFoundInDriveException) {
        emit(DriveInitialLoading());
        return;
      }

      if (e is DriveNotFoundException) {
        emit(DriveDetailLoadNotFound());
        return;
      }

      logger.e('An error occured mouting the drive explorer', e);
    });

    await _folderSubscription?.asFuture();
  }

  List<ArDriveDataTableItem> parseEntitiesToDatatableItem({
    required FolderWithContents folder,
    required bool isOwner,
  }) {
    int index = 0;

    final folders = folder.subfolders.map(
      (folder) => DriveDataTableItemMapper.fromFolderEntry(
        folder,
        index++,
        isOwner,
      ),
    );

    final files = folder.files.map(
      (file) => DriveDataTableItemMapper.toFileDataTableItem(
        file,
        index++,
        isOwner,
      ),
    );

    final items = [
      ...folders,
      ...files,
    ];

    return items;
  }

  List<int> calculateRowsPerPage(int totalEntries) {
    List<int> availableRowsPerPage;
    if (totalEntries < _defaultAvailableRowsPerPage.first) {
      availableRowsPerPage = <int>[totalEntries];
    } else {
      availableRowsPerPage = _defaultAvailableRowsPerPage;
    }
    return availableRowsPerPage;
  }

  Future<void> selectDataItem(ArDriveDataTableItem item,
      {bool openSelectedPage = false}) async {
    var state = this.state as DriveDetailLoadSuccess;

    if (state.currentDrive.isPublic && item is FileDataTableItem) {
      final dataTxId = item.dataTxId;
      state = state.copyWith(
          selectedFilePreviewUrl:
              '${_configService.config.defaultArweaveGatewayUrl}/$dataTxId');
    }

    _selectedItem = item;

    int? selectedPage;

    if (openSelectedPage) {
      selectedPage =
          state.currentFolderContents.indexOf(item) ~/ state.rowsPerPage;
    }

    emit(
      state.copyWith(
        selectedItem: item,
        showSelectedItemDetails: true,
        selectedPage: selectedPage,
        forceRebuildKey: selectedPage != null ? UniqueKey() : null,
      ),
    );
  }

  ArDriveDataTableItem? _selectedItem;

  ArDriveDataTableItem? get selectedItem => _selectedItem;

  Future<void> selectItems(List<ArDriveDataTableItem> items) async {
    var state = this.state as DriveDetailLoadSuccess;

    bool hasFolderSelected = false;

    if (items.any((element) => element is FolderDataTableItem)) {
      hasFolderSelected = true;
    }

    _selectedItems = items;

    if (items.isEmpty) {
      emit(state.copyWith(multiselect: false, hasFoldersSelected: false));
    } else {
      emit(state.copyWith(
        multiselect: true,
        hasFoldersSelected: hasFolderSelected,
      ));
    }
  }

  Future<void> unselectItem(SelectedItem selectedItem) async {
    var state = this.state as DriveDetailLoadSuccess;
    final updatedSelectedItems = state.selectedItems
        .where((element) => element.id != selectedItem.id)
        .toList();
    state = state.multiselect
        ? state.copyWith(selectedItems: updatedSelectedItems)
        : state.copyWith(selectedItems: []);

    emit(state);
    // Close multiselect automatically if no file is selected
    if (state.selectedItems.isEmpty && state.multiselect) {
      state = state.copyWith(multiselect: false);
      Future.delayed(
        const Duration(milliseconds: 10),
      ).then((value) => emit(state));
    }
  }

  void setMultiSelect(bool multiSelect) {
    final state = this.state as DriveDetailLoadSuccess;

    if (state.multiselect == multiSelect) return;

    if (!multiSelect) {
      clearSelection();
    }

    if (_selectedItems.isNotEmpty) {
      emit(state.copyWith(multiselect: true));
    } else {
      emit(state.copyWith(multiselect: false));
    }
  }

  Future<void> clearSelection() async {
    _selectedItems.clear();
  }

  bool get forceDisableMultiselect {
    if (_forceDisableMultiselect) {
      _forceDisableMultiselect = false;
      return true;
    }

    return false;
  }

  set forceDisableMultiselect(bool value) {
    _forceDisableMultiselect = value;
  }

  Future<void> launchPreview(TxID dataTxId) => openUrl(
      url: '${_configService.config.defaultArweaveGatewayUrl}/$dataTxId');

  void sortFolder({
    DriveOrder contentOrderBy = DriveOrder.name,
    OrderingMode contentOrderingMode = OrderingMode.asc,
  }) {
    final state = this.state as DriveDetailLoadSuccess;
    openFolder(
      folderId: state.folderInView.folder.id,
      contentOrderBy: contentOrderBy,
      contentOrderingMode: contentOrderingMode,
    );
  }

  void toggleSelectedItemDetails() {
    final state = this.state as DriveDetailLoadSuccess;
    if (state.showSelectedItemDetails) {
      _selectedItem = null;
    }

    emit(
      state.copyWith(showSelectedItemDetails: !state.showSelectedItemDetails),
    );
  }

  void refreshDriveDataTable() async {
    _refreshSelectedItem = true;

    if (state is DriveDetailLoadSuccess) {
      await Future.delayed(const Duration(milliseconds: 100));
      final state = this.state as DriveDetailLoadSuccess;
      emit(state.copyWith(
        forceRebuildKey: UniqueKey(),
      ));
    }
  }

  bool canNavigateThroughImages(bool showHiddenImages) {
    final numberOfImages = getAllImagesOfCurrentFolder(showHiddenImages).length;
    return numberOfImages > 1;
  }

  Future<void> selectNextImage(bool showHiddenImages) =>
      _selectImageRelativeToCurrent(1, showHiddenImages);
  Future<void> selectPreviousImage(bool showHiddenImages) =>
      _selectImageRelativeToCurrent(-1, showHiddenImages);

  Future<void> _selectImageRelativeToCurrent(
      int offset, bool showHiddenImages) async {
    final currentIndex = getIndexForImage(
      _selectedItem as FileDataTableItem,
      showHiddenImages,
    );
    final nextIndex = currentIndex + offset;
    final nextImage = getImageForIndex(nextIndex, showHiddenImages);

    await selectDataItem(nextImage);
  }

  FileDataTableItem getImageForIndex(int index, bool showHiddenImages) {
    final allImagesOfCurrentFolder =
        getAllImagesOfCurrentFolder(showHiddenImages);
    final cyclicIndex = index % allImagesOfCurrentFolder.length;
    final image = allImagesOfCurrentFolder[cyclicIndex];

    return image;
  }

  int getIndexForImage(FileDataTableItem image, bool showHiddenImages) {
    final allImagesOfCurrentFolder =
        getAllImagesOfCurrentFolder(showHiddenImages);
    final index = allImagesOfCurrentFolder.indexWhere(
      (element) => element.id == image.id,
    );

    return index;
  }

  List<FileDataTableItem> getAllImagesOfCurrentFolder(bool showHiddenImages) {
    if (_allImagesOfCurrentFolder != null) {
      return _allImagesOfCurrentFolder!;
    }

    final state = this.state as DriveDetailLoadSuccess;

    final List<FileDataTableItem> allImagesForFolder =
        state.currentFolderContents.whereType<FileDataTableItem>().where(
      (element) {
        final supportedImageType = supportedImageTypesInFilePreview.contains(
          element.contentType,
        );

        return supportedImageType &&
            (showHiddenImages ? true : !element.isHidden);
      },
    ).toList();

    _allImagesOfCurrentFolder = allImagesForFolder;

    return allImagesForFolder;
  }

  Future<void> updateTableColumnVisibility(TableColumn column) async {
    (await _store()).putBool(
      'drive_detail_column_${column.index}',
      column.isVisible,
    );
  }

  Future<Map<int, bool>> getTableColumnVisibility() async {
    final columnVisibility = <int, bool>{};

    for (int i = 0; i < 5; i++) {
      final isVisible = (await _store()).getBool(
        'drive_detail_column_$i',
      );

      columnVisibility[i] = isVisible ?? true;
    }

    return columnVisibility;
  }

  Future<LocalKeyValueStore> _store() async {
    return LocalKeyValueStore.getInstance();
  }

  @override
  Future<void> close() {
    _folderSubscription?.cancel();
    _allImagesOfCurrentFolder = null;
    return super.close();
  }
}

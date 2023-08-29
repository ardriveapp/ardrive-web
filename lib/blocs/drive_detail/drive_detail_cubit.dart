import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

part 'drive_detail_state.dart';

class DriveDetailCubit extends Cubit<DriveDetailState> {
  final String driveId;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ConfigService _configService;
  final ArDriveAuth _auth;

  StreamSubscription? _folderSubscription;
  final _defaultAvailableRowsPerPage = [25, 50, 75, 100];

  List<ArDriveDataTableItem> _selectedItems = [];
  List<ArDriveDataTableItem> get selectedItems => _selectedItems;

  bool _forceDisableMultiselect = false;

  bool _refreshSelectedItem = false;

  DriveDetailCubit({
    required this.driveId,
    String? initialFolderId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ConfigService configService,
    required ArDriveAuth auth,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _auth = auth,
        _configService = configService,
        super(DriveDetailLoadInProgress()) {
    if (driveId.isEmpty) {
      return;
    }

    if (initialFolderId != null) {
      // TODO: Handle deep-linking folders of unattached drives.
      Future.microtask(() async {
        final folder = await _driveDao
            .folderById(driveId: driveId, folderId: initialFolderId)
            .getSingleOrNull();
        // Open the root folder if the deep-linked folder could not be found.

        openFolder(path: folder?.path ?? rootPath);
        // The empty string here is required to open the root folder
      });
    } else {
      openFolder(path: rootPath);
    }
  }

  void openFolder({
    required String path,
    DriveOrder contentOrderBy = DriveOrder.name,
    OrderingMode contentOrderingMode = OrderingMode.asc,
  }) async {
    try {
      _selectedItem = null;

      emit(DriveDetailLoadInProgress());

      await _folderSubscription?.cancel();
      // For attaching drives. If drive is not found, emit state to prompt drive attach
      await _driveDao
          .driveById(driveId: driveId)
          .getSingleOrNull()
          .then((value) async {
        logger.d('Drive with id $driveId found');

        if (value == null) {
          logger.d('Drive with id $driveId not found');

          emit(DriveDetailLoadNotFound());
          return;
        }

        try {
          await _driveDao.getFolderTree(driveId, value.rootFolderId);
        } catch (e) {
          logger.d('Folder with id ${value.rootFolderId} not found');

          emit(DriveInitialLoading());
          return;
        }
      });

      _folderSubscription =
          Rx.combineLatest3<Drive, FolderWithContents, ProfileState, void>(
        _driveDao.driveById(driveId: driveId).watchSingle(),
        _driveDao.watchFolderContents(
          driveId,
          folderPath: path,
          orderBy: contentOrderBy,
          orderingMode: contentOrderingMode,
        ),
        _profileCubit.stream.startWith(ProfileCheckingAvailability()),
        (drive, folderContents, _) async {
          final state = this.state is DriveDetailLoadSuccess
              ? this.state as DriveDetailLoadSuccess
              : null;

          final profile = _profileCubit.state;

          var availableRowsPerPage = _defaultAvailableRowsPerPage;

          availableRowsPerPage = calculateRowsPerPage(
            folderContents.files.length + folderContents.subfolders.length,
          );

          final rootFolderNode =
              await _driveDao.getFolderTree(driveId, drive.rootFolderId);

          if (_selectedItem != null && _refreshSelectedItem) {
            if (_selectedItem is FileDataTableItem) {
              final index = folderContents.files.indexWhere(
                (element) => element.id == _selectedItem!.id,
              );

              if (index >= 0) {
                _selectedItem = DriveDataTableItemMapper.toFileDataTableItem(
                  folderContents.files[index],
                  _selectedItem!.index,
                  _selectedItem!.isOwner,
                );
              }
            } else if (_selectedItem is FolderDataTableItem) {
              final index = folderContents.subfolders.indexWhere(
                (element) => element.id == _selectedItem!.id,
              );
              if (index >= 0) {
                _selectedItem = DriveDataTableItemMapper.fromFolderEntry(
                  folderContents.subfolders[index],
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

            _refreshSelectedItem = false;
          }

          final currentFolderContents = parseEntitiesToDatatableItem(
            folder: folderContents,
            isOwner: isDriveOwner(_auth, drive.ownerAddress),
          );

          if (state != null) {
            emit(
              state.copyWith(
                selectedItem: _selectedItem,
                currentDrive: drive,
                hasWritePermissions: profile is ProfileLoggedIn &&
                    drive.ownerAddress == profile.walletAddress,
                folderInView: folderContents,
                contentOrderBy: contentOrderBy,
                contentOrderingMode: contentOrderingMode,
                rowsPerPage: availableRowsPerPage.first,
                availableRowsPerPage: availableRowsPerPage,
                currentFolderContents: currentFolderContents,
              ),
            );
          } else {
            emit(
              DriveDetailLoadSuccess(
                selectedItem: _selectedItem,
                currentDrive: drive,
                hasWritePermissions: profile is ProfileLoggedIn &&
                    drive.ownerAddress == profile.walletAddress,
                folderInView: folderContents,
                contentOrderBy: contentOrderBy,
                contentOrderingMode: contentOrderingMode,
                rowsPerPage: availableRowsPerPage.first,
                availableRowsPerPage: availableRowsPerPage,
                driveIsEmpty: rootFolderNode.isEmpty(),
                multiselect: false,
                currentFolderContents: currentFolderContents,
              ),
            );
          }
        },
      ).listen((_) {});
    } catch (e, stacktrace) {
      logger.e('An error occured mouting the drive explorer', e, stacktrace);
    }
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

  void setRowsPerPage(int rowsPerPage) {
    switch (state.runtimeType) {
      case DriveDetailLoadSuccess:
        emit(
          (state as DriveDetailLoadSuccess).copyWith(
            rowsPerPage: rowsPerPage,
          ),
        );
    }
  }

  Future<void> selectDataItem(ArDriveDataTableItem item) async {
    var state = this.state as DriveDetailLoadSuccess;

    if (state.currentDrive.isPublic && item is FileDataTableItem) {
      final fileWithRevisions = _driveDao.latestFileRevisionByFileId(
        driveId: driveId,
        fileId: item.id,
      );
      final dataTxId = (await fileWithRevisions.getSingle()).dataTxId;
      state = state.copyWith(
          selectedFilePreviewUrl:
              '${_configService.config.defaultArweaveGatewayUrl}/$dataTxId');
    }

    _selectedItem = item;

    emit(state.copyWith(selectedItem: item, showSelectedItemDetails: true));
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
      state = state.copyWith(multiselect: false, hasFoldersSelected: false);
    } else {
      emit(state.copyWith(
          multiselect: true, hasFoldersSelected: hasFolderSelected));
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
      path: state.folderInView.folder.path,
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

  void refreshDriveDataTable() {
    _refreshSelectedItem = true;

    if (state is DriveDetailLoadSuccess) {
      emit((state as DriveDetailLoadSuccess).copyWith());
    }
  }

  @override
  Future<void> close() {
    _folderSubscription?.cancel();
    return super.close();
  }
}

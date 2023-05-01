import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

class DriveExplorerProvider extends ChangeNotifier {
  DriveExplorerProvider({
    required this.drive,
    required DriveDao driveDao,
    required ArDriveAuth auth,
    required SyncCubit syncCubit,
    required AppActivity appActivity,
  })  : _driveDao = driveDao,
        _appActivity = appActivity,
        _syncCubit = syncCubit,
        _auth = auth {
    Future.microtask(() async {
      final folder = await _driveDao
          .folderById(driveId: drive.id, folderId: drive.rootFolderId)
          .getSingleOrNull();

      openFolder(folder?.path ?? rootPath);
    });
  }

  final DriveDao _driveDao;
  final ArDriveAuth _auth;
  final SyncCubit _syncCubit;
  final AppActivity _appActivity;

  Drive drive;

  DriveExplorer? _driveExplorer;

  DriveExplorer? get driveExplorer => _driveExplorer;

  List<ArDriveDataTableItem> _selectedItems = [];

  List<ArDriveDataTableItem> get selectedItems => _selectedItems;

  ArDriveDataTableItem? _selectedItem;

  ArDriveDataTableItem? get selectedItem => _selectedItem;

  bool _isMultiSelectMode = false;

  bool get isMultiSelectMode => _isMultiSelectMode;

  set isMultiSelectMode(bool value) {
    _isMultiSelectMode = value;
    notifyListeners();
  }

  void openFolder(String path) async {
    logger.d('loadCurrentFolder: $path');
    Rx.combineLatest3(
        _driveDao.driveById(driveId: drive.id).watchSingle(),
        _driveDao.watchFolderContents(
          drive.id,
          folderPath: path,
          orderBy: DriveOrder.lastUpdated,
          orderingMode: OrderingMode.asc,
        ),
        _appActivity.stream.startWith(_appActivity.currentEvent),
        (drive, folderContents, appActivity) async {
      logger.d('app activity: ${appActivity.toString()}');

      if (appActivity.isGeneratingPaths || appActivity.isSyncing) {
        return;
      }

      final currentFolderContents = parseEntitiesToDatatableItem(
        folder: folderContents,
        isOwner: isDriveOwner(_auth, drive.ownerAddress),
      );

      _driveExplorer = DriveExplorer(
        folderInView: DriveDataTableItemMapper.fromFolderEntry(
          folderContents.folder,
          (selected) {
            openFolder(selected.path);
          },
          0,
          isDriveOwner(_auth, drive.ownerAddress),
        ),
      );

      driveExplorer?._items = currentFolderContents;

      notifyListeners();
    }).listen((event) {});
  }

  List<ArDriveDataTableItem> parseEntitiesToDatatableItem({
    required FolderWithContents folder,
    required bool isOwner,
  }) {
    int index = 0;

    final folders = folder.subfolders.map(
      (folder) => DriveDataTableItemMapper.fromFolderEntry(
        folder,
        (selected) {
          openFolder(folder.path);
        },
        index++,
        isOwner,
      ),
    );

    final files = folder.files.map(
      (file) => DriveDataTableItemMapper.toFileDataTableItem(
        file,
        (selected) async {
          // if (file.id == _selectedItem?.id) {
          //   toggleSelectedItemDetails();
          // } else {
          //   selectDataItem(selected);
          // }
        },
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

  openDriveRoot(Drive drive) {
    this.drive = drive;
    openFolder('');
  }

  selectItem(ArDriveDataTableItem item) {
    _selectedItem = item;
    notifyListeners();
  }

  unselectItem() {
    _selectedItem = null;
    notifyListeners();
  }

  selectItems(List<ArDriveDataTableItem> items) {
    _selectedItems = items;
    notifyListeners();
  }

  void updateSelectedItem() {
    // _selectedItem = _driveExplorer!._items
    //     .firstWhere((element) => element.id == _selectedItem!.id);

    notifyListeners();
  }
}

class DriveExplorer {
  DriveExplorer({
    required this.folderInView,
  });

  final FolderDataTableItem folderInView;

  List<ArDriveDataTableItem> _items = [];

  List<ArDriveDataTableItem> get items => _items;
}

class AppActivity {
  final StreamController<AppActivityEvent> _streamController =
      StreamController.broadcast();

  AppActivityEvent _currentEvent = AppActivityEvent(
    isGeneratingPaths: false,
    isSyncing: false,
  );

  AppActivityEvent get currentEvent => _currentEvent;

  void addEvent(AppActivityEvent event) {
    _currentEvent = event;
    _streamController.add(event);
  }

  Stream<AppActivityEvent> get stream => _streamController.stream;
}

class AppActivityEvent {
  final bool isGeneratingPaths;
  final bool isSyncing;

  AppActivityEvent({
    required this.isGeneratingPaths,
    required this.isSyncing,
  });

  // copy with
  AppActivityEvent copyWith({
    bool? isGeneratingPaths,
    bool? isSyncing,
  }) {
    return AppActivityEvent(
      isGeneratingPaths: isGeneratingPaths ?? this.isGeneratingPaths,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }

  // to strign
  @override
  String toString() =>
      'AppActivityEvent(isGeneratingPaths: $isGeneratingPaths, isSyncing: $isSyncing)';
}

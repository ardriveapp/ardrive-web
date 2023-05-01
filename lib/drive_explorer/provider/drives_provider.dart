import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

class DrivesProvider extends ChangeNotifier {
  DrivesProvider({
    required DriveDao driveDao,
    required ArDriveAuth auth,
  })  : _driveDao = driveDao,
        _auth = auth {
    _auth.onAuthStateChanged().listen((user) {
      if (user == null) {
        cleanDrives();
        return;
      }
    });
  }

  final DriveDao _driveDao;
  final ArDriveAuth _auth;

  List<Drive> _userPublicDrives = [];
  List<Drive> _userPrivateDrives = [];
  List<Drive> _sharedDrives = [];

  List<Drive> get userPublicDrives => _userPublicDrives;
  List<Drive> get userPrivateDrives => _userPrivateDrives;
  List<Drive> get sharedDrives => _sharedDrives;

  Drive? _currentDrive;

  Drive? get currentDrive => _currentDrive;

  Future<void> loadDrives() async {
    logger.d('loadDrives');

    _driveDao
        .allDrives(order: OrderBy([OrderingTerm.asc(_driveDao.drives.name)]))
        .watch()
        .listen((event) {
      logger.d('loaded drives');
      _userPublicDrives =
          event.where((element) => element.privacy == 'public').toList();
      _userPrivateDrives =
          event.where((element) => element.privacy == 'private').toList();

      _sharedDrives = event
          .where((element) => !isDriveOwner(_auth, element.ownerAddress))
          .toList();
      _currentDrive = _userPublicDrives.first;

      notifyListeners();
    });
  }

  selectDrive(Drive drive) {
    _currentDrive = drive;
    notifyListeners();
  }

  Future<void> cleanDrives() async {
    await _driveDao.deleteDrivesAndItsChildren();

    _userPublicDrives = [];
    _userPrivateDrives = [];
    _sharedDrives = [];
  }
}

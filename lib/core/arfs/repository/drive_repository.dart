import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';

class DriveRepository {
  final DriveDao _driveDao;
  final ArDriveAuth _auth;

  DriveRepository({
    required DriveDao driveDao,
    required ArDriveAuth auth,
  })  : _driveDao = driveDao,
        _auth = auth;

  Future<List<Drive>> getAllUserDrives() async {
    final allDrives = await _driveDao.allDrives().get();

    return allDrives
        .where((element) =>
            element.ownerAddress == _auth.currentUser.walletAddress)
        .toList();
  }

  Future<List<FileWithLatestRevisionTransactions>> getAllFileEntriesInDrive({
    required String driveId,
  }) async {
    final files = await _driveDao
        .filesInDriveWithRevisionTransactions(driveId: driveId)
        .get();

    return files;
  }
}

import 'package:ardrive/models/daos/daos.dart';

class DriveRepository {
  final DriveDao _driveDao;

  DriveRepository({
    required DriveDao driveDao,
  }) : _driveDao = driveDao;

  Future<List<FileWithLatestRevisionTransactions>> getAllFileEntriesInDrive({
    required String driveId,
  }) async {
    final files = await _driveDao
        .filesInDriveWithRevisionTransactions(driveId: driveId)
        .get();

    return files;
  }
}

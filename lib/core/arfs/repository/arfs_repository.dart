import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/models/models.dart';

abstract class ARFSRepository {
  Future<ARFSDriveEntity> getDriveById(String id);

  factory ARFSRepository(DriveDao driveDao, ARFSFactory arfsFactory) =>
      _ARFSRepository(driveDao, arfsFactory);
}

class _ARFSRepository implements ARFSRepository {
  _ARFSRepository(this._driveDao, this.arfsFactory);

  final DriveDao _driveDao;
  final ARFSFactory arfsFactory;

  @override
  Future<ARFSDriveEntity> getDriveById(String id) async {
    final drive = await _driveDao.driveById(driveId: id).getSingle();

    return arfsFactory.getARFSDriveFromDriveDAOEntity(drive);
  }
}

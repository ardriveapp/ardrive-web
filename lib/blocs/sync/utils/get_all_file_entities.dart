part of 'package:ardrive/blocs/sync/sync_cubit.dart';

Future<List<FileRevision>> _getAllFileEntities({
  required DriveDao driveDao,
}) async {
  return await driveDao.db.fileRevisions.select().get();
}

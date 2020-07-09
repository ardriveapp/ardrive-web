import 'dart:io';

import 'package:moor/moor.dart';
import 'package:moor_ffi/moor_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'daos/daos.dart';
import 'models/models.dart';

part 'database.g.dart';

@UseMoor(
    tables: [Drives, FolderEntries, FileEntries], daos: [DrivesDao, DriveDao])
class Database extends _$Database {
  Database() : super(_openConnection());

  @override
  int get schemaVersion => -200;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(join(dbFolder.path, 'db.sqlite'));
    return VmDatabase(file);
  });
}

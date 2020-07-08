import 'package:sqflite/sqflite.dart';
import '../models/drive.dart';
import 'drive_repository.dart';

class SqfliteDriveRepository implements DriveRepository {
  final Database _db;

  SqfliteDriveRepository({Database db}) : _db = db;

  @override
  Stream<List<Drive>> drives() {
    return null;
  }

  @override
  Future<void> addDrive(Drive drive) {
    // TODO: implement addDrive
    throw UnimplementedError();
  }

  @override
  Future<void> updateDrive(Drive drive) {
    // TODO: implement updateDrive
    throw UnimplementedError();
  }
}

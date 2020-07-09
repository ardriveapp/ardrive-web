import '../models/drive.dart';

class DriveRepository {
  Stream<List<Drive>> drives() {}

  Future<void> addDrive(Drive drive) {}

  Future<void> updateDrive(Drive drive) {}
}

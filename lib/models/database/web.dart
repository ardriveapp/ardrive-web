import 'package:drift/drift.dart';
import 'package:drift/web.dart';

LazyDatabase openConnection() {
  return LazyDatabase(
    () async => WebDatabase.withStorage(
      await DriftWebStorage.indexedDbIfSupported('db'),
    ),
  );
}

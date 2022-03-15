import 'package:moor/moor.dart';
import 'package:moor/moor_web.dart';

LazyDatabase openConnection() {
  return LazyDatabase(
    () async => WebDatabase.withStorage(
      await MoorWebStorage.indexedDbIfSupported('db'),
    ),
  );
}

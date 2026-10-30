import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

LazyDatabase openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase(file);
  });
}

/// Publications are web only; off the web this is a plain in-memory
/// database, so the same start-up code compiles and runs in tests.
LazyDatabase openPublicationConnection() {
  return LazyDatabase(() async => NativeDatabase.memory());
}

/// Deletes the database file, for a start that cannot open it.
Future<bool> deleteLocalDatabase() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  final file = File(join(dbFolder.path, 'db.sqlite'));
  for (final path in [file.path, '${file.path}-journal']) {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
  return true;
}

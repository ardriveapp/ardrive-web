import 'package:drift/drift.dart';

LazyDatabase openConnection() {
  throw 'Platform not supported';
}

LazyDatabase openPublicationConnection() {
  throw 'Platform not supported';
}

Future<List<String>> deleteLegacyLocalStores() async => const [];

bool get webDatabaseIsWriter => true;

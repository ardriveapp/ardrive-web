import 'package:moor/moor.dart';
import 'package:moor/moor_web.dart';

LazyDatabase openConnection() => LazyDatabase(() async =>
    WebDatabase.withStorage(await MoorWebStorage.indexedDbIfSupported('db')));

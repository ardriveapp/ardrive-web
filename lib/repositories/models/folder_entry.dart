import 'package:moor/moor.dart';

import 'folder_item.dart';

@DataClassName('FolderEntry')
class FolderEntries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1)();
  TextColumn get path => text().withLength(min: 1)();
  TextColumn get items => text().map(const FolderItemsConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

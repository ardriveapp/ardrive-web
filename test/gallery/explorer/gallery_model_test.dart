import 'package:ardrive/gallery/explorer/gallery_model.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/models/drive_table_columns.dart';
import 'package:ardrive_ui/ardrive_ui.dart' show TableSort;
import 'package:flutter_test/flutter_test.dart';

import 'gallery_test_items.dart';

String type(ArDriveDataTableItem i) => i.contentType;

GalleryModel build(
  List<ArDriveDataTableItem> items, {
  int? column,
  TableSort? order,
}) =>
    buildGalleryModel(
      items,
      sortColumn: column,
      sortOrder: order,
      typeLabel: type,
      toLocal: false,
    );

List<String> ids(Iterable<ArDriveDataTableItem> items) =>
    items.map((e) => e.id).toList();

void main() {
  final oct1 = DateTime(2026, 10, 3);
  final oct2 = DateTime(2026, 10, 20);
  final sep = DateTime(2026, 9, 12);
  final aug = DateTime(2025, 8, 30);

  group('months', () {
    test('files are grouped by month, newest month first by default', () {
      final model = build([
        fileItem('a', created: sep),
        fileItem('b', created: oct1),
        fileItem('c', created: aug),
        fileItem('d', created: oct2),
      ]);
      expect(model.months.map((m) => m.id), ['2026-10', '2026-09', '2025-08']);
      // Inside a month the folder's own order is kept.
      expect(ids(model.months.first.items), ['b', 'd']);
    });

    test('folders come first and are not grouped', () {
      final model = build([
        fileItem('a', created: oct1),
        folderItem('f1'),
        fileItem('b', created: sep),
        folderItem('f2'),
      ]);
      expect(ids(model.folders), ['f1', 'f2']);
      expect(ids(model.flat), ['f1', 'f2', 'a', 'b']);
      expect(model.months, hasLength(2));
    });

    test('an empty folder has nothing', () {
      final model = build(const []);
      expect(model.flat, isEmpty);
      expect(model.months, isEmpty);
    });

    // The list's arrow is inverted: the first click on a date column (asc)
    // puts the newest first, and so months do too.
    test('months are by date created, except under Last updated', () {
      final items = [
        fileItem('a', created: aug, updated: oct1),
        fileItem('b', created: sep, updated: sep),
      ];
      expect(
        build(items, column: ColumnIndexes.name, order: TableSort.asc)
            .months
            .map((m) => m.id),
        ['2026-09', '2025-08'],
      );
      expect(
        build(items, column: ColumnIndexes.lastUpdated, order: TableSort.asc)
            .months
            .map((m) => m.id),
        ['2026-10', '2026-09'],
      );
    });
  });

  group('sort parity with the list', () {
    // The list sorts with sortExplorerRows; so must the gallery.
    final items = [
      fileItem('p', name: 'pier.jpg', created: sep, size: 50),
      fileItem('a', name: 'Alfama.jpg', created: oct2, size: 900),
      fileItem('z', name: 'zoo.png', created: oct1, size: 10),
      fileItem('m',
          name: 'map.pdf',
          contentType: 'application/pdf',
          created: aug,
          size: 300),
      folderItem('Beta'),
      folderItem('alpha'),
    ];

    for (final column in [
      ColumnIndexes.name,
      ColumnIndexes.size,
      ColumnIndexes.lastUpdated,
      ColumnIndexes.dateCreated,
      ColumnIndexes.type,
    ]) {
      for (final order in TableSort.values) {
        test('column $column ${order.name}: folders and files in list order',
            () {
          final expected = ids(sortExplorerRows(
            items,
            column,
            order,
            typeLabel: type,
          ));
          final model = build(items, column: column, order: order);

          // Folders, in the list's order.
          expect(ids(model.folders),
              expected.where((id) => id == 'Beta' || id == 'alpha').toList());

          final dateSort = column == ColumnIndexes.lastUpdated ||
              column == ColumnIndexes.dateCreated;
          if (dateSort) {
            // Months follow the sort, so the whole order is the list's.
            expect(ids(model.flat), expected);
          } else {
            // Months are by date, but inside each one the sort's order holds.
            for (final month in model.months) {
              final inList = expected
                  .where((id) => month.items.any((e) => e.id == id))
                  .toList();
              expect(ids(month.items), inList);
            }
          }
        });
      }
    }

    test('no column picked: the folder\'s own order, folders first', () {
      final model = build(items);
      expect(ids(model.folders), ['Beta', 'alpha']);
      expect(
        ids(model.months.expand((m) => m.items)).toSet(),
        {'p', 'a', 'z', 'm'},
      );
    });
  });

  test('sortExplorerRows, the list\'s own sort: folders first, each sorted',
      () {
    final rows = <ArDriveDataTableItem>[
      fileItem('z', name: 'zoo.jpg'),
      folderItem('f2', name: 'Beta'),
      fileItem('a', name: 'alfama.jpg'),
      folderItem('f1', name: 'alpha'),
    ];
    // The list's `asc` is the order its header's first click gives, which
    // the table has always run from the end of the alphabet; kept as is.
    expect(
      ids(sortExplorerRows(rows, ColumnIndexes.name, TableSort.asc,
          typeLabel: type)),
      ['f2', 'f1', 'z', 'a'],
    );
    expect(
      ids(sortExplorerRows(rows, ColumnIndexes.name, TableSort.desc,
          typeLabel: type)),
      ['f1', 'f2', 'a', 'z'],
    );
  });

  test('galleryDateOf picks the date the sort uses', () {
    final f = fileItem('a', created: aug, updated: oct1);
    expect(galleryDateOf(f, ColumnIndexes.lastUpdated), oct1);
    expect(galleryDateOf(f, ColumnIndexes.name), aug);
    expect(galleryDateOf(f, null), aug);
  });
}

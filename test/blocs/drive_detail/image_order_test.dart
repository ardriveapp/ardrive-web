import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/models/drive_table_columns.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../gallery/explorer/gallery_test_items.dart';

String type(ArDriveDataTableItem item) => item.contentType;

void main() {
  final oct = DateTime(2026, 10, 15);
  final sep = DateTime(2026, 9, 15);
  // The folder's own order: c, a, doc, b, hidden, d.
  final c = fileItem('c', name: 'c.jpg', created: sep);
  final a = fileItem('a', name: 'a.jpg', created: oct);
  final doc = fileItem('doc',
      name: 'notes.pdf', contentType: 'application/pdf', created: oct);
  final b = fileItem('b', name: 'b.jpg', created: oct);
  final hidden = fileItem('h', name: 'h.jpg', created: oct, isHidden: true);
  final d = fileItem('d', name: 'd.jpg', created: DateTime(2026, 11, 1));
  final contents = <ArDriveDataTableItem>[c, a, doc, b, hidden, d];

  List<String> ids(List<FileDataTableItem> items) =>
      items.map((i) => i.id).toList();

  test('the list with no sort chosen: the folder\'s own order, photos only',
      () {
    expect(
      ids(imagesInViewOrder(contents,
          gallery: false,
          sortColumn: null,
          sortOrder: null,
          typeLabel: type,
          showHidden: false)),
      ['c', 'a', 'b', 'd'],
    );
  });

  test('the list sorted: exactly the order the table shows', () {
    for (final order in TableSort.values) {
      final shown =
          sortExplorerRows(contents, ColumnIndexes.name, order, typeLabel: type)
              .whereType<FileDataTableItem>()
              .where((f) => f.contentType == 'image/jpeg' && !f.isHidden)
              .map((f) => f.id)
              .toList();
      expect(
        ids(imagesInViewOrder(contents,
            gallery: false,
            sortColumn: ColumnIndexes.name,
            sortOrder: order,
            typeLabel: type,
            showHidden: false)),
        shown,
        reason: '$order',
      );
    }
  });

  test('the gallery: newest month first, as its months are drawn', () {
    final order = ids(imagesInViewOrder(contents,
        gallery: true,
        sortColumn: null,
        sortOrder: null,
        typeLabel: type,
        showHidden: false));
    expect(order.first, 'd'); // November
    expect(order.last, 'c'); // September
    expect(order.toSet(), {'a', 'b', 'c', 'd'});
  });

  test('hidden photos only when hidden items are shown', () {
    expect(
      imagesInViewOrder(contents,
              gallery: false,
              sortColumn: null,
              sortOrder: null,
              typeLabel: type,
              showHidden: true)
          .map((i) => i.id),
      contains('h'),
    );
  });

  group('imageBeside', () {
    final images = [a, b, c];

    test('the next and previous', () {
      expect(imageBeside(images, 'b', 1)?.id, 'c');
      expect(imageBeside(images, 'b', -1)?.id, 'a');
    });

    test('the ends are ends: nothing after the last or before the first', () {
      expect(imageBeside(images, 'c', 1), isNull);
      expect(imageBeside(images, 'a', -1), isNull);
    });

    test('nothing for a photo that is not there', () {
      expect(imageBeside(images, 'zzz', 1), isNull);
    });
  });
}

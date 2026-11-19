import 'package:ardrive/gallery/explorer/gallery_selection.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gallery_test_items.dart';

void main() {
  final a = fileItem('a');
  final b = fileItem('b');
  final c = fileItem('c');
  final d = fileItem('d');
  final ordered = <ArDriveDataTableItem>[a, b, c, d];

  GallerySelectionChange click(
    ArDriveDataTableItem item,
    GalleryClickKind kind, {
    List<ArDriveDataTableItem> multi = const [],
    ArDriveDataTableItem? selected,
    ArDriveDataTableItem? anchor,
  }) =>
      resolveGalleryClick(
        item: item,
        kind: kind,
        ordered: ordered,
        multiSelected: multi,
        selected: selected,
        anchor: anchor,
      );

  List<String> ids(List<ArDriveDataTableItem>? items) =>
      items!.map((e) => e.id).toList();

  test('a click chooses that item and nothing else', () {
    final change = click(b, GalleryClickKind.plain);
    expect(change.select, b);
    expect(change.selectMany, isNull);
    expect(change.anchor, b);
  });

  test('a click ends a multi-selection', () {
    final change = click(c, GalleryClickKind.plain, multi: [a, b]);
    expect(change.select, c);
    expect(change.selectMany, isEmpty);
  });

  test('Ctrl adds an item, counting the clicked one as the first', () {
    final change = click(c, GalleryClickKind.toggle, selected: a);
    expect(ids(change.selectMany), ['a', 'c']);
    expect(change.select, isNull);
  });

  test('Ctrl on a chosen item takes it out; the last one out ends it', () {
    expect(
      ids(click(b, GalleryClickKind.toggle, multi: [a, b]).selectMany),
      ['a'],
    );
    expect(
      click(a, GalleryClickKind.toggle, multi: [a]).selectMany,
      isEmpty,
    );
  });

  test('Shift chooses the range from the anchor, in display order', () {
    final change = click(d, GalleryClickKind.range, selected: b, anchor: b);
    expect(ids(change.selectMany), ['b', 'c', 'd']);
    // The anchor stays, so the next Shift extends from it.
    expect(change.anchor, b);
  });

  test('Shift works upward too, and falls back to the chosen item', () {
    expect(
      ids(click(a, GalleryClickKind.range, anchor: c).selectMany),
      ['a', 'b', 'c'],
    );
    expect(
      ids(click(c, GalleryClickKind.range, selected: b).selectMany),
      ['b', 'c'],
    );
  });

  test('Shift with nothing to start from chooses just the item', () {
    expect(ids(click(c, GalleryClickKind.range).selectMany), ['c']);
  });
}

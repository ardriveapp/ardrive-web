import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_utils/mocks.dart';

/// A hidden item, shown, is faded as a whole - every cell, by the same amount
/// in both themes. It was drawn in a flat grey, the same in both themes, and a
/// low text colour alone barely dims it in the light theme.
void main() {
  DriveExplorerItemTile tile({required bool isHidden}) => DriveExplorerItemTile(
        name: 'secret.txt',
        size: '17 B',
        lastUpdated: DateTime(2026, 10, 23),
        dateCreated: DateTime(2026, 10, 23),
        license: '',
        onPressed: () {},
        isHidden: isHidden,
        typography: ArDriveTypographyNew.desktop,
        dataTableItem: createMockFileDataTableItem(name: 'secret.txt'),
        colorTokens: ArDriveColorTokens.lightMode(),
      );

  test('fades every cell of a hidden row', () {
    final cells = tile(isHidden: true).row;
    expect(cells, everyElement(isA<Opacity>()));
    expect(cells.map((c) => (c as Opacity).opacity), everyElement(0.45));
  });

  test('leaves a visible row alone', () {
    expect(tile(isHidden: false).row.whereType<Opacity>(), isEmpty);
  });
}

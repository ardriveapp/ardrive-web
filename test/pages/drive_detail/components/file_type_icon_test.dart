import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A keyfile is JSON, and Phil asked for JSON files to look like it: braces,
  // not the generic page every other text file gets.
  test('JSON files get the JSON icon', () {
    for (final type in [
      'application/json',
      'text/json',
      'application/json; charset=utf-8',
      'application/ld+json',
      'application/geo+json',
    ]) {
      expect(getIconForContentType(type).icon, ArDriveIcons.json().icon,
          reason: type);
    }
  });

  test('a manifest keeps its own icon though it is JSON too', () {
    expect(
      getIconForContentType('application/x.arweave-manifest+json').icon,
      ArDriveIcons.manifest().icon,
    );
  });

  test('other code stays a page', () {
    expect(getIconForContentType('text/javascript').icon,
        ArDriveIcons.fileOutlined().icon);
  });
}

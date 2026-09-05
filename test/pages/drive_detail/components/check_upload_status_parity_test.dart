import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The menu that exists twice.
///
/// `drive_explorer_item_tile.dart` builds item actions in two places - the row
/// kebab (`DriveExplorerItemTileTrailing`) and the details panel
/// (`EntityActionsMenu`) - and an item written into one of them is an item half
/// the app does not have. Not hypothetical: "Check upload status" shipped into
/// the row kebab alone, so the panel somebody opens to find out why a file is
/// showing an amber dot could do nothing about it.
///
/// This reads the source rather than pumping a widget, deliberately. The
/// failure mode is an *omission* across two copies, and a widget test proves
/// only that the arrangement it happened to build works - it cannot notice the
/// copy nobody wired up. Reading the file is what answers "do both offer this?".
void main() {
  final source = File(
    'lib/pages/drive_detail/components/drive_explorer_item_tile.dart',
  ).readAsStringSync();

  test('both item menus offer the pending-upload check', () {
    // One definition, plus one call from each menu.
    final uses = 'checkUploadStatusDropdownItem('.allMatches(source).length;

    expect(
      uses,
      3,
      reason: 'fewer means a menu has lost the item; more means a third menu '
          'appeared that this test has not been told about',
    );
  });

  test('each menu gates it on the file actually being pending', () {
    final gates =
        RegExp(r'fileStatusFromTransactions == TransactionStatus\.pending')
            .allMatches(source)
            .length;

    expect(
      gates,
      2,
      reason: 'on a confirmed file the item does nothing, and an item that is '
          'present and inert is worse than one that is absent',
    );
  });
}

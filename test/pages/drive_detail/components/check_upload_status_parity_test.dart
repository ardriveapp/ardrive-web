import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The menu that exists twice, and the branch it has to be in.
///
/// `drive_explorer_item_tile.dart` builds item actions in two places - the row
/// kebab (`DriveExplorerItemTileTrailing`) and the details panel
/// (`EntityActionsMenu`) - and each of those splits by item type: folders,
/// drives, and a fallthrough that handles files. An item written into one menu
/// is an item half the app does not have; an item written into the wrong branch
/// of the right menu is worse, because it looks present and is offered to the
/// wrong thing.
///
/// Both have now happened to "Check upload status" in turn. It first shipped
/// into the row kebab alone, so the details panel could not act on a pending
/// file. The fix for that then put it in the panel's `DriveDataItem` branch, so
/// the panel's *file* menu still did not have it and a drive was offered an
/// action about a file's upload.
///
/// The first version of this test counted call sites, which caught the omission
/// and missed the misplacement entirely - a count cannot say where. This asks
/// the question that actually matters: is it in the branch that handles files?
void main() {
  final source = File(
    'lib/pages/drive_detail/components/drive_explorer_item_tile.dart',
  ).readAsStringSync();

  /// The body of `_getItems` for each of the two menus, split at the point
  /// where the type branches give way to the file fallthrough.
  ///
  /// Every branch above that point is guarded by `item is <something not a
  /// file>`; the fallthrough below it casts to `FileDataTableItem`, which is
  /// what makes it the file branch.
  List<String> fileBranches() {
    const marker = 'file: item as FileDataTableItem';
    final regions = <String>[];

    for (final match in RegExp(marker).allMatches(source)) {
      // From the `return [` that opens the fallthrough to the end of its list.
      final open = source.lastIndexOf('return [', match.start);
      final close = source.indexOf('\n    ];', open);
      regions.add(source.substring(open, close == -1 ? match.end : close));
    }

    return regions;
  }

  List<String> nonFileBranches() {
    final regions = <String>[];

    for (final marker in [
      'if (item is FolderDataTableItem) {',
      '} else if (item is DriveDataItem) {',
    ]) {
      for (final match in RegExp(RegExp.escape(marker)).allMatches(source)) {
        final close = source.indexOf('\n    }', match.end);
        regions.add(source.substring(match.end, close == -1 ? match.end : close));
      }
    }

    return regions;
  }

  test('both menus offer the pending check on their file branch', () {
    final branches = fileBranches();

    expect(branches, hasLength(2), reason: 'one file branch per menu');

    for (final branch in branches) {
      expect(
        branch.contains('checkUploadStatusDropdownItem('),
        isTrue,
        reason: 'a file menu without it is half the app missing the feature',
      );
      expect(
        branch.contains(
          'fileStatusFromTransactions == TransactionStatus.pending',
        ),
        isTrue,
        reason: 'on a confirmed file the item does nothing, and one that is '
            'present and inert is worse than one that is absent',
      );
    }
  });

  test('no folder or drive branch offers it', () {
    for (final branch in nonFileBranches()) {
      expect(
        branch.contains('checkUploadStatusDropdownItem('),
        isFalse,
        reason: 'a drive has no upload status, and a folder has no transaction '
            'of its own to check',
      );
    }
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The pending-upload check belongs to a file and only to a file. Every
/// surface builds its menus from item_menus.dart, so that is where it has to
/// sit: on the file menu, behind the pending status, and nowhere else.
void main() {
  final source = File(
    'lib/pages/drive_detail/components/item_menus.dart',
  ).readAsStringSync();

  String builder(String name) {
    final start = source.indexOf('List<ArDriveDropdownItem> $name(');
    expect(start, isNot(-1), reason: '$name is the one $name');
    final next = source.indexOf('\nList<ArDriveDropdownItem> ', start + 1);
    return source.substring(start, next == -1 ? source.length : next);
  }

  test('the file menu offers the pending check, only while pending', () {
    final files = builder('fileMenuItems');
    expect(files.contains('checkUploadStatusDropdownItem('), isTrue,
        reason: 'a file menu without it is half the app missing the feature');
    expect(
      files.contains('fileStatusFromTransactions == TransactionStatus.pending'),
      isTrue,
      reason: 'on a confirmed file the item does nothing, and one that is '
          'present and inert is worse than one that is absent',
    );
  });

  test('no folder or drive menu offers it', () {
    for (final name in ['folderMenuItems', 'driveMenuItems']) {
      expect(builder(name).contains('checkUploadStatusDropdownItem('), isFalse,
          reason: 'a drive has no upload status, and a folder has no '
              'transaction of its own to check');
    }
  });
}

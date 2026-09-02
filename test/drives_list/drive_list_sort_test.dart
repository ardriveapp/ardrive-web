import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/domain/drive_list_sort.dart';
import 'package:flutter_test/flutter_test.dart';

DriveListItem _drive(
  String name, {
  int? fileCount,
  int? totalSize,
  DateTime? lastSyncedAt,
  DateTime? dateCreated,
}) =>
    DriveListItem(
      id: name,
      name: name,
      isPrivate: false,
      isSharedWithMe: false,
      isHidden: false,
      dateCreated: dateCreated ?? DateTime(2024),
      hasBeenWalked: fileCount != null,
      fileCount: fileCount,
      totalSize: totalSize,
      lastSyncedAt: lastSyncedAt,
      isSyncing: false,
      lastSyncFailed: false,
    );

List<String> _sorted(
  List<DriveListItem> drives,
  DriveListSort sort, {
  required bool ascending,
}) =>
    ([...drives]..sort(sort.comparator(ascending: ascending)))
        .map((d) => d.name)
        .toList();

/// Ordering the drives list, and the one rule that is easy to get wrong.
///
/// Three columns are withheld until a drive has been walked - the row shows a
/// dash, not a zero. A dash is not a small number: it means the app has not
/// looked. Sorting it as zero fills the top of an ascending list with drives
/// nobody has read, which is the opposite of what asking for the smallest is
/// for.
void main() {
  group('unknown figures sort last, whichever way the arrow points', () {
    final drives = [
      _drive('read-small', fileCount: 2, totalSize: 10),
      _drive('unread'),
      _drive('read-large', fileCount: 90, totalSize: 900),
    ];

    test('files ascending puts the unread drive last, not first', () {
      expect(
        _sorted(drives, DriveListSort.files, ascending: true),
        ['read-small', 'read-large', 'unread'],
      );
    });

    test('and files descending leaves it last too', () {
      expect(
        _sorted(drives, DriveListSort.files, ascending: false),
        ['read-large', 'read-small', 'unread'],
      );
    });

    test('size behaves the same way', () {
      expect(
        _sorted(drives, DriveListSort.size, ascending: true),
        ['read-small', 'read-large', 'unread'],
      );
      expect(
        _sorted(drives, DriveListSort.size, ascending: false),
        ['read-large', 'read-small', 'unread'],
      );
    });

    test('as does a drive that has never been synced', () {
      final withSyncTimes = [
        _drive('older', lastSyncedAt: DateTime(2024, 1, 1)),
        _drive('never'),
        _drive('newer', lastSyncedAt: DateTime(2024, 6, 1)),
      ];

      expect(
        _sorted(withSyncTimes, DriveListSort.lastSynced, ascending: false),
        ['newer', 'older', 'never'],
      );
      expect(
        _sorted(withSyncTimes, DriveListSort.lastSynced, ascending: true),
        ['older', 'newer', 'never'],
      );
    });
  });

  group('the order is total', () {
    test('drives that tie fall back to their names, both directions', () {
      final tied = [
        _drive('Charlie', fileCount: 5),
        _drive('alpha', fileCount: 5),
        _drive('Bravo', fileCount: 5),
      ];

      // The tie-break is by name and does not invert with the column, so a
      // reversed sort of equal values is not a reshuffle.
      expect(
        _sorted(tied, DriveListSort.files, ascending: true),
        ['alpha', 'Bravo', 'Charlie'],
      );
      expect(
        _sorted(tied, DriveListSort.files, ascending: false),
        ['alpha', 'Bravo', 'Charlie'],
      );
    });

    test('several unread drives keep a stable order among themselves', () {
      final unread = [_drive('zulu'), _drive('alpha'), _drive('mike')];

      expect(
        _sorted(unread, DriveListSort.size, ascending: true),
        ['alpha', 'mike', 'zulu'],
      );
    });
  });

  group('name and created', () {
    test('name reverses', () {
      final drives = [_drive('bravo'), _drive('alpha')];

      expect(_sorted(drives, DriveListSort.name, ascending: true),
          ['alpha', 'bravo']);
      expect(_sorted(drives, DriveListSort.name, ascending: false),
          ['bravo', 'alpha']);
    });

    test('created is never unknown, so nothing is pushed to the bottom', () {
      final drives = [
        _drive('old', dateCreated: DateTime(2020)),
        _drive('new', dateCreated: DateTime(2026)),
      ];

      expect(_sorted(drives, DriveListSort.created, ascending: false),
          ['new', 'old']);
    });
  });
}

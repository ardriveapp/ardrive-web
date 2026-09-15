import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sidebar's section headings, turned into the navigation.
///
/// They used to sit above a second copy of the drive list the table was already
/// showing in full - and pushed Private and Shared below however many public
/// drives the wallet had, so on a real account they were off screen.
void main() {
  DriveListItem drive({
    required String id,
    bool isPrivate = false,
    bool isSharedWithMe = false,
    bool isHidden = false,
  }) =>
      DriveListItem(
        id: id,
        name: id,
        isPrivate: isPrivate,
        isSharedWithMe: isSharedWithMe,
        isHidden: isHidden,
        dateCreated: DateTime(2026, 1, 1),
        hasBeenWalked: true,
        fileCount: 1,
        totalSize: 1,
        lastSyncedAt: null,
        isSyncing: false,
        lastSyncFailed: false,
      );

  final all = [
    drive(id: 'public-1'),
    drive(id: 'public-2'),
    drive(id: 'private-1', isPrivate: true),
    drive(id: 'shared-1', isSharedWithMe: true),
    drive(id: 'hidden-1', isHidden: true),
    drive(id: 'hidden-private', isPrivate: true, isHidden: true),
  ];

  List<String> shown(DriveScope scope) =>
      all.where(scope.matches).map((d) => d.id).toList();

  test('All drives is everything except what the user hid', () {
    expect(shown(DriveScope.all),
        ['public-1', 'public-2', 'private-1', 'shared-1']);
  });

  test('each scope shows only its own, and never a hidden drive', () {
    expect(shown(DriveScope.public), ['public-1', 'public-2', 'shared-1']);
    expect(shown(DriveScope.private), ['private-1']);
    expect(shown(DriveScope.sharedWithMe), ['shared-1']);
  });

  test('Hidden shows exactly what the others withhold', () {
    expect(shown(DriveScope.hidden), ['hidden-1', 'hidden-private']);
  });

  test('the counts are of everything, not of what is on screen', () {
    // A scope reading zero is the fact a reader wants *before* clicking it, so
    // the counts cannot be derived from the filtered list.
    final counts = DriveScopeCounts.of(all);

    expect(counts[DriveScope.all], 4);
    expect(counts[DriveScope.private], 1);
    expect(counts[DriveScope.hidden], 2);
  });

  test('an empty wallet counts zero rather than throwing', () {
    final counts = DriveScopeCounts.of([]);

    for (final scope in DriveScope.values) {
      expect(counts[scope], 0);
    }
  });
}

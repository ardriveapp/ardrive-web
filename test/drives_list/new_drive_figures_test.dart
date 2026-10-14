import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the list says about a drive this device made and filled.
///
/// The user creates their first drive, uploads a few files, and opens Your
/// Drives. Nothing has read that drive from chain - `createDrive` inserts with
/// no block height and the schema defaults it to zero - but the files are in
/// `fileEntries`, written by the upload. Treating "never walked" as "nothing
/// known" showed them `Never synced`, a dash, and a dash, over work they had
/// just done.
void main() {
  DriveListItem drive({
    required bool hasBeenWalked,
    int? fileCount,
    int? totalSize,
  }) =>
      DriveListItem(
        id: 'drive-a',
        name: 'My Drive',
        isPrivate: false,
        isSharedWithMe: false,
        isHidden: false,
        dateCreated: DateTime(2026, 3, 1),
        hasBeenWalked: hasBeenWalked,
        fileCount: fileCount,
        totalSize: totalSize,
        lastSyncedAt: null,
        isSyncing: false,
        lastSyncFailed: false,
      );

  group('the sync-everything card', () {
    test('is offered when nothing is known about anything', () {
      final state = DrivesListLoaded(
        drives: [drive(hasBeenWalked: false)],
      );

      expect(state.nothingHasEverBeenSynced, isTrue);
    });

    /// The card says "their contents have not been fetched yet". They have.
    test('is withdrawn once a drive has figures to show', () {
      final state = DrivesListLoaded(
        drives: [drive(hasBeenWalked: false, fileCount: 5, totalSize: 2048)],
      );

      expect(
        state.nothingHasEverBeenSynced,
        isFalse,
        reason: 'a brand new drive the user has already uploaded to is not a '
            'wallet with nothing in it',
      );
    });

    test('is still offered beside a drive that is known to be empty', () {
      // Walked, and genuinely holds nothing. Zero here is a fact, not a gap -
      // but this drive *has* been read, so the card goes anyway.
      final state = DrivesListLoaded(
        drives: [drive(hasBeenWalked: true, fileCount: 0, totalSize: 0)],
      );

      expect(state.nothingHasEverBeenSynced, isFalse);
    });

    test('is still offered when one unread drive sits beside another', () {
      final state = DrivesListLoaded(
        drives: [drive(hasBeenWalked: false), drive(hasBeenWalked: false)],
      );

      expect(state.nothingHasEverBeenSynced, isTrue);
    });
  });
}

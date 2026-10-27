import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// A drive's unfiltered history returns every entity with its `Drive-Id`,
/// publications and drive states among them. Sync parses neither, so it must
/// not download them: a publication's manifest is about 82 KB, a drive state
/// can be megabytes, and each body would land in the metadata cache.
void main() {
  Map<String, String> entity(String type, {bool sealed = false}) => {
        EntityTag.entityType: type,
        EntityTag.driveId: 'drive',
        if (sealed) EntityTag.cipherIv: 'iv',
      };

  test('publications, drive states and snapshots are never fetched', () {
    for (final type in [
      EntityTypeTag.publication,
      EntityTypeTag.driveState,
      EntityTypeTag.snapshot,
    ]) {
      expect(
          syncFetchesEntityData(entity(type), isPrivateDrive: false), isFalse,
          reason: type);
      expect(
          syncFetchesEntityData(entity(type, sealed: true),
              isPrivateDrive: true),
          isFalse,
          reason: 'a private drive\'s $type');
    }
  });

  test('drives, folders and files are', () {
    for (final type in [
      EntityTypeTag.drive,
      EntityTypeTag.folder,
      EntityTypeTag.file,
    ]) {
      expect(syncFetchesEntityData(entity(type), isPrivateDrive: false), isTrue,
          reason: type);
      expect(
          syncFetchesEntityData(entity(type, sealed: true),
              isPrivateDrive: true),
          isTrue,
          reason: type);
    }
  });

  test("a private drive's entity with no Cipher-IV is not", () {
    expect(
        syncFetchesEntityData(entity(EntityTypeTag.file), isPrivateDrive: true),
        isFalse);
  });
}

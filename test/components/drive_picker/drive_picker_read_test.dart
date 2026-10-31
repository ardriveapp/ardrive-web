import 'package:ardrive/components/drive_picker/drive_picker_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

/// The picker's reads against a real database: what each purpose offers.
void main() {
  late Database db;
  late DriveDao dao;
  late Drive site;
  late Drive unread;

  FolderEntriesCompanion folder(
    String id,
    String name, {
    String driveId = 'site',
    String? parent = 'site-root',
    bool hidden = false,
    bool ghost = false,
  }) =>
      FolderEntriesCompanion.insert(
        id: id,
        driveId: driveId,
        name: name,
        path: '',
        parentFolderId: Value(parent),
        isHidden: Value(hidden),
        isGhost: Value(ghost),
      );

  FileEntriesCompanion file(
    String id,
    String name, {
    String parent = 'site-root',
    bool hidden = false,
    String? pinnedBy,
    String? contentType,
  }) =>
      FileEntriesCompanion.insert(
        id: id,
        driveId: 'site',
        name: name,
        parentFolderId: parent,
        path: '',
        size: 1,
        lastModifiedDate: DateTime(2026),
        dataTxId: '$id-data',
        dataContentType: Value(contentType),
        isHidden: Value(hidden),
        pinnedDataOwnerAddress: Value(pinnedBy),
      );

  setUp(() async {
    db = getTestDb();
    dao = db.driveDao;
    await db.batch((b) {
      for (final (id, name) in [('site', 'Site'), ('unread', 'Unread')]) {
        b.insert(
          db.drives,
          DrivesCompanion.insert(
            id: id,
            rootFolderId: '$id-root',
            ownerAddress: 'me',
            name: name,
            privacy: DrivePrivacyTag.public,
          ),
        );
      }
      b.insert(
          db.drives,
          DrivesCompanion.insert(
            id: 'other',
            rootFolderId: 'other-root',
            ownerAddress: 'me',
            name: 'Other',
            privacy: DrivePrivacyTag.public,
          ));
      b.insertAll(db.folderEntries, [
        folder('site-root', 'Site', parent: null),
        folder('docs', 'Docs'),
        folder('secret', 'Secret', hidden: true),
        folder('ghost', 'Ghost', ghost: true),
        folder('other-root', 'Other', driveId: 'other', parent: null),
        folder('elsewhere', 'Elsewhere',
            driveId: 'other', parent: 'other-root'),
      ]);
      b.insertAll(db.fileEntries, [
        file('logo', 'logo.png'),
        file('old', 'old.png', hidden: true),
        file('theirs', 'theirs.pdf', pinnedBy: 'someone'),
        file('typed', 'notes', contentType: 'text/plain'),
      ]);
    });
    // Site was synced here; the others were only listed.
    await (db.update(db.drives)..where((d) => d.id.equals('site')))
        .write(const DrivesCompanion(lastBlockHeight: Value(100)));
    site = await dao.driveById(driveId: 'site').getSingle();
    unread = await dao.driveById(driveId: 'unread').getSingle();
  });

  tearDown(() => db.close());

  DrivePickerRead read(DrivePickerPurpose purpose) =>
      drivePickerReadFrom(dao, purpose: purpose);

  test('lists a root without its hidden folders and files', () async {
    final root = await read(DrivePickerPurpose.upload)(site, null);

    expect(root!.id, 'site-root');
    expect(root.parentFolderId, isNull, reason: 'the root has no parent');
    expect(root.folders.map((f) => f.id), isNot(contains('secret')));
    expect(root.files.map((f) => f.id), isNot(contains('old')));
    expect(root.files.map((f) => f.id), containsAll(['logo', 'theirs']));
  });

  test("files carry their type, their name's when they have none", () async {
    final root = await read(DrivePickerPurpose.publish)(site, null);
    final types = {for (final f in root!.files) f.id: f.contentType};

    expect(types['logo'], 'image/png');
    expect(types['typed'], 'text/plain');
    expect(root.files.singleWhere((f) => f.id == 'theirs').isPinned, isTrue);
    expect(root.files.singleWhere((f) => f.id == 'logo').isPinned, isFalse);
  });

  test("a folder of another drive is not read as this drive's", () async {
    expect(await read(DrivePickerPurpose.upload)(site, 'elsewhere'), isNull);
  });

  test('a drive this device has not read is not read', () async {
    expect(await read(DrivePickerPurpose.upload)(unread, null), isNull);
  });

  /// Reading the drive list stores a placeholder for a drive's root and no
  /// block height. The folder row is there, so the folder alone cannot say
  /// the drive was never read: that is the drive's synced status, by the
  /// rule the explorer and Your drives use.
  test('a drive with only a placeholder root is not read', () async {
    await db.into(db.folderEntries).insert(
          folder('unread-root', 'Unread', driveId: 'unread', parent: null),
        );
    expect(await dao.folderById(folderId: 'unread-root').getSingleOrNull(),
        isNotNull,
        reason: 'the placeholder is there');
    expect(await dao.driveIdsSyncedHere(), isNot(contains('unread')));

    for (final purpose in DrivePickerPurpose.values) {
      expect(await read(purpose)(unread, null), isNull);
    }

    // The Sync prompt, with nothing to upload or publish into.
    final cubit = DrivePickerCubit(
        drives: [unread], read: read(DrivePickerPurpose.upload));
    addTearDown(cubit.close);
    await cubit.openDrive(unread);
    expect(cubit.state.unreadable, isTrue);
  });

  test('the same drive reads once a sync has walked it', () async {
    await db.into(db.folderEntries).insert(
          folder('unread-root', 'Unread', driveId: 'unread', parent: null),
        );
    await (db.update(db.drives)..where((d) => d.id.equals('unread')))
        .write(const DrivesCompanion(lastBlockHeight: Value(5)));

    final root = await read(DrivePickerPurpose.upload)(unread, null);
    expect(root!.id, 'unread-root');
  });

  group('ghost folders', () {
    test('are offered for an upload, as the explorer offers them', () async {
      final root = await read(DrivePickerPurpose.upload)(site, null);
      expect(root!.folders.map((f) => f.id), contains('ghost'));
    });

    test('are not offered for publishing, as the item menus do not', () async {
      final root = await read(DrivePickerPurpose.publish)(site, null);
      expect(root!.folders.map((f) => f.id), ['docs']);
      expect(await read(DrivePickerPurpose.publish)(site, 'ghost'), isNull);
    });
  });

  group('a hidden folder opened directly', () {
    test('opens for an upload: it was the folder open in the explorer',
        () async {
      final cubit = DrivePickerCubit(
        drives: [site],
        read: read(DrivePickerPurpose.upload),
      );
      addTearDown(cubit.close);

      await cubit.start(driveId: 'site', folderId: 'secret');

      expect(cubit.state.folder?.id, 'secret');
    });

    test("opens the drive's root for publishing: nothing hidden publishes",
        () async {
      final cubit = DrivePickerCubit(
        drives: [site],
        read: read(DrivePickerPurpose.publish),
      );
      addTearDown(cubit.close);

      await cubit.start(driveId: 'site', folderId: 'secret');

      expect(cubit.state.folder?.id, 'site-root');
    });
  });
}

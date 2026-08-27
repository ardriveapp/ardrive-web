/// Shared fixture: a file-backed sink/source, and a drive built directly in
/// the real Drift schema.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';
import 'package:drift/drift.dart';

/// The VM/CLI implementation. The browser implementation writes to the sqlite3
/// WASM virtual filesystem instead; both are proven in
/// `test/drive_state_prototype` on the PE-9205-attach-vfs-prototype branch.
class FileArtifactSink implements ArtifactSink {
  @override
  final String path;
  FileArtifactSink(this.path);

  @override
  Future<int> size() => File(path).length();

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  @override
  Future<void> dispose() async {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}

class FileArtifactSource implements ArtifactSource {
  @override
  final String path;
  FileArtifactSource(this.path);

  static Future<FileArtifactSource> of(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes);
    return FileArtifactSource(path);
  }

  @override
  Future<void> dispose() async {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}

/// Real transaction ids are 32 bytes of entropy rendered as 43 base64url
/// characters, and they are roughly a third of an artifact by size. A fixture
/// that interpolates a counter into them compresses far better than reality —
/// `#2188` hit exactly that and its first measurement was wrong by 4.5x
/// because of it. So these are random, from a fixed seed for repeatability.
final _rng = Random(20260827);
String txId() {
  final bytes = List<int>.generate(32, (_) => _rng.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

const testDriveId = '0a36156c-6274-41a2-87b0-372f4da7f568';
const testOwner = 'owner-address-under-test';
const plantedSecret = 'PE9205-ENCRYPTED-WALLET-MUST-NEVER-BE-PUBLISHED';

/// Builds a drive in the *real* schema — same tables the app uses, created by
/// drift's own migration — plus a profile and a second drive, so the export
/// has something it must not pick up.
Future<void> seedDrive(
  GeneratedDatabase db, {
  int files = 200,
  int folders = 20,
  String driveId = testDriveId,
  String privacy = 'private',
}) async {
  await db.customStatement(
    'INSERT OR REPLACE INTO profiles (id, username, encryptedWallet, keySalt, '
    'walletPublicKey, encryptedPublicKey, profileType) '
    "VALUES ('p1', 'tester', ?, ?, 'pubkey', ?, 0)",
    [
      Uint8List.fromList(plantedSecret.codeUnits),
      Uint8List.fromList(List.filled(32, 7)),
      Uint8List.fromList(List.filled(32, 8)),
    ],
  );

  await db.customStatement(
    'INSERT OR REPLACE INTO drives (id, rootFolderId, ownerAddress, name, '
    'privacy, encryptedKey, keyEncryptionIv, syncCursor, lastBlockHeight, '
    'isHidden, dateCreated, lastUpdated) '
    "VALUES (?, 'root-$driveId', ?, 'A drive', ?, ?, ?, 'CURSOR-SECRET', "
    '1814228, 0, 1700000000, 1700000000)',
    [
      driveId,
      testOwner,
      privacy,
      Uint8List.fromList(List.filled(32, 9)),
      Uint8List.fromList(List.filled(12, 3)),
    ],
  );

  await db.transaction(() async {
    for (var i = 0; i < folders; i++) {
      await db.customStatement(
        'INSERT INTO folder_entries (id, driveId, name, parentFolderId, path, '
        'dateCreated, lastUpdated, isGhost, isHidden) '
        'VALUES (?, ?, ?, ?, ?, 1700000000, 1700000000, 0, 0)',
        ['folder-$i', driveId, 'Folder $i', 'root-$driveId', '/Folder $i'],
      );
      await db.customStatement(
        'INSERT INTO folder_revisions (folderId, driveId, name, '
        'parentFolderId, metadataTxId, dateCreated, action, isHidden) '
        "VALUES (?, ?, ?, ?, ?, ?, 'create', 0)",
        [
          'folder-$i',
          driveId,
          'Folder $i',
          'root-$driveId',
          txId(),
          1700000000 + i,
        ],
      );
    }

    for (var i = 0; i < files; i++) {
      final folder = 'folder-${i % folders}';
      final dataTx = txId();
      await db.customStatement(
        'INSERT INTO file_entries (id, driveId, name, parentFolderId, path, '
        'size, lastModifiedDate, dataContentType, dataTxId, isHidden, '
        'dateCreated, lastUpdated) '
        "VALUES (?, ?, ?, ?, ?, ?, 1700000000, 'application/pdf', ?, 0, "
        '1700000000, 1700000000)',
        [
          'file-$i',
          driveId,
          'document_$i.pdf',
          folder,
          '/Folder ${i % folders}/document_$i.pdf',
          1000 + i,
          dataTx,
        ],
      );
      await db.customStatement(
        'INSERT INTO file_revisions (fileId, driveId, name, parentFolderId, '
        'size, lastModifiedDate, dataContentType, metadataTxId, dataTxId, '
        'dateCreated, action, isHidden) '
        "VALUES (?, ?, ?, ?, ?, 1700000000, 'application/pdf', ?, ?, ?, "
        "'create', 0)",
        [
          'file-$i',
          driveId,
          'document_$i.pdf',
          folder,
          1000 + i,
          txId(),
          dataTx,
          1700000000 + i,
        ],
      );
    }

    await db.customStatement(
      'INSERT INTO drive_revisions (driveId, rootFolderId, ownerAddress, '
      'name, privacy, metadataTxId, dateCreated, action, isHidden) '
      "VALUES (?, ?, ?, 'A drive', ?, ?, 1700000000, 'create', 0)",
      [
        driveId,
        'root-$driveId',
        testOwner,
        privacy,
        txId(),
      ],
    );
  });
}

bool bytesContain(Uint8List haystack, String needle) {
  final n = needle.codeUnits;
  outer:
  for (var i = 0; i + n.length <= haystack.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (haystack[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

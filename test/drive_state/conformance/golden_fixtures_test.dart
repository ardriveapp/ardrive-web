@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/models/models.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';
import 'golden_fixtures.dart';

/// Writes the fixtures when `DRIVE_STATE_WRITE_FIXTURES=1`:
///
///     flutter test test/drive_state/conformance/golden_fixtures_test.dart \
///       --dart-define=x=y   # any run with the variable in the environment
///
/// Otherwise checks them: the checked-in bytes still get the outcome they
/// record from this app's importer, and building them again gives the same
/// payloads, tags and outcomes.
void main() {
  final write = Platform.environment['DRIVE_STATE_WRITE_FIXTURES'] == '1';

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test('building the fixtures again gives what is checked in', () async {
    final built = await buildGoldenFixtures();

    if (write) {
      final dir = Directory(fixturesPath)..createSync(recursive: true);
      for (final old in dir.listSync().whereType<File>()) {
        if (old.path.endsWith('.bin') || old.path.endsWith('.json')) {
          old.deleteSync();
        }
      }
      const encoder = JsonEncoder.withIndent('  ');
      for (final fixture in built) {
        File('${dir.path}/${fixture.name}.bin').writeAsBytesSync(fixture.body);
        File('${dir.path}/${fixture.name}.json')
            .writeAsStringSync('${encoder.convert(fixture.toSidecar())}\n');
      }
    }

    final checkedIn = _checkedIn();
    expect(
      checkedIn.keys.toSet(),
      built.map((f) => f.name).toSet(),
      reason: 'run with DRIVE_STATE_WRITE_FIXTURES=1 to write them',
    );

    for (final fixture in built) {
      final sidecar = checkedIn[fixture.name]!;
      // The sealed bytes are not compared: gzip writes the time into its
      // header. Everything a reader is judged on is.
      final fresh = jsonDecode(jsonEncode(fixture.toSidecar()));
      expect(fresh['transaction'], sidecar['transaction'],
          reason: fixture.name);
      expect(fresh['reader'], sidecar['reader'], reason: fixture.name);
      expect(fresh['payloadSha256'], sidecar['payloadSha256'],
          reason: fixture.name);
      // Not `detail`: this app's reason is for people, and carries timings.
      for (final key in ['outcome', 'tables']) {
        expect(fresh['expected'][key], sidecar['expected'][key],
            reason: '${fixture.name}: $key');
      }
    }
  });

  group('every checked-in fixture gets the outcome it records', () {
    for (final entry in _checkedIn().entries) {
      test(entry.key, () async {
        final sidecar = entry.value;
        final body = File('$fixturesPath/${sidecar['body']}').readAsBytesSync();
        final result = await _importChecked(sidecar, body);

        expect(
          result.outcome.name,
          sidecar['expected']['outcome'],
          reason: '${sidecar['description']}\n${result.detail}',
        );
      });
    }
  });
}

/// Every sidecar under [fixturesPath], by fixture name.
Map<String, Map<String, dynamic>> _checkedIn() {
  final dir = Directory(fixturesPath);
  if (!dir.existsSync()) return {};
  return {
    for (final file in dir.listSync().whereType<File>())
      if (file.path.endsWith('.json'))
        (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['name']
                as String:
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
  };
}

/// Imports a checked-in fixture from its sidecar alone, the way a second
/// reader has to: nothing from [buildGoldenFixtures].
Future<DriveStateImportResult> _importChecked(
  Map<String, dynamic> sidecar,
  Uint8List body,
) async {
  final reader = sidecar['reader'] as Map<String, dynamic>;
  final transaction = sidecar['transaction'] as Map<String, dynamic>;
  final privacy = reader['privacy'] as String;
  final isPrivate = privacy == 'private';
  final key = reader['driveKey'] as String?;

  final db = getTestDb();
  try {
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: reader['driveId'] as String,
            rootFolderId: fixtureRootFolderId,
            ownerAddress: reader['ownerAddress'] as String,
            name: 'A drive the reader has not synced',
            privacy: privacy,
            encryptedKey: isPrivate
                ? Value(Uint8List.fromList([1, 2, 3, 4]))
                : const Value(null),
            keyEncryptionIv: isPrivate
                ? Value(Uint8List.fromList([5, 6, 7]))
                : const Value(null),
            driveKeyGenerated: Value(isPrivate),
            lastBlockHeight: Value(reader['syncedToBlock'] as int),
            lastUpdated: Value(DateTime.utc(2020)),
          ),
        );

    final tags = <String, String>{};
    for (final tag in transaction['tags'] as List) {
      tags.putIfAbsent(tag['name'] as String, () => tag['value'] as String);
    }

    return await DriveStateImporter(db.driveDao).import(
      candidate: DriveStateArtifactCandidate(
        txId: transaction['id'] as String,
        ownerAddress: transaction['owner'] as String,
        tags: tags,
      ),
      body: body,
      protection: DriveStateProtection.forDrive(
        privacy: privacy,
        driveKey:
            key == null ? null : SecretKey(utils.decodeBase64ToBytes(key)),
      ).protection!,
      expectedOwnerAddress: reader['ownerAddress'] as String,
    );
  } finally {
    await db.close();
  }
}

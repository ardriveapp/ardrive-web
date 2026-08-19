import 'dart:typed_data';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/data/drive_state_sync_source.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _MockImporter extends Mock implements DriveStateImporter {}

class _FakeCandidate extends Fake implements DriveStateArtifactCandidate {}

/// Discovery that hands back a whole candidate list, the way the GraphQL
/// implementation does — newest first, and more than one of them.
class _ListDiscovery implements DriveStateDiscovery {
  _ListDiscovery(this.candidates);

  final List<DriveStateArtifactCandidate> candidates;

  @override
  Future<DriveStateDiscoveryResult> findCandidates({
    required String driveId,
    required String ownerAddress,
    int? minBlockHeight,
  }) async =>
      DriveStateDiscoveryResult(candidates: candidates);
}

/// FINDING 4 — [DriveStateSyncSource] reads `discovered.newest` and nothing
/// else. Every other candidate the same query returned is discarded the moment
/// the newest one fails, so one unusable artifact takes the whole feature off
/// for that drive and the sync walks the range it was built to skip.
///
/// This is not a rare state. An L1 artifact is indexed by GraphQL before its
/// data is retrievable from a gateway, so *every* publication opens a window in
/// which the newest candidate 404s and a perfectly good previous artifact —
/// already in the list, already ordered — is never tried. A newest artifact
/// that is permanently unseeded closes the feature for that drive for good.
void main() {
  const driveId = 'drive-id';
  const ownerAddress = 'owner-address';

  final driveKey = SecretKey(List.filled(32, 7));
  final body = Uint8List.fromList([1, 2, 3]);

  late MockArweaveService arweave;
  late _MockImporter importer;

  setUpAll(() {
    registerFallbackValue(_FakeCandidate());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(SecretKey(const []));
  });

  DriveStateArtifactCandidate candidate(String txId, int blockEnd) =>
      DriveStateArtifactCandidate(
        txId: txId,
        ownerAddress: ownerAddress,
        tags: {
          EntityTag.entityType: EntityTypeTag.driveState,
          EntityTag.driveId: driveId,
          EntityTag.stateVersion: '1.0',
          EntityTag.blockStart: '0',
          EntityTag.blockEnd: '$blockEnd',
          EntityTag.entityCount: '3',
        },
      );

  setUp(() {
    arweave = MockArweaveService();
    importer = _MockImporter();

    when(() => importer.import(
          candidate: any(named: 'candidate'),
          body: any(named: 'body'),
          driveKey: any(named: 'driveKey'),
          expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
        )).thenAnswer(
      (invocation) async => DriveStateImportResult.imported(
        const DriveStateImportStats(
          foldersWritten: 2,
          filesWritten: 1,
          revisionsWritten: 3,
          licensesWritten: 0,
          transactionsWritten: 5,
          rowsKeptLocallyNewer: 0,
          watermark: 800,
          parseDuration: Duration(milliseconds: 1),
          mergeDuration: Duration(milliseconds: 1),
        ),
      ),
    );
  });

  Future<DriveStateSyncResult> read(DriveStateDiscovery discovery) =>
      DriveStateSyncSource(
        arweave: arweave,
        discovery: discovery,
        importer: importer,
        reporter: const DriveStateOutcomeReporter(sink: _swallow),
      ).read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        driveKey: driveKey,
        lastBlockHeight: 100,
      );

  test('falls back to the next candidate when the newest cannot be fetched',
      () async {
    // Just published, indexed, not yet retrievable.
    when(() => arweave.getEntityDataFromNetwork(
          txId: 'just-published',
          largeBody: any(named: 'largeBody'),
        )).thenThrow(Exception('404 from the gateway'));
    // Last week's artifact, seeded and fine.
    when(() => arweave.getEntityDataFromNetwork(
          txId: 'last-weeks',
          largeBody: any(named: 'largeBody'),
        )).thenAnswer((_) async => body);

    final result = await read(_ListDiscovery([
      candidate('just-published', 900),
      candidate('last-weeks', 800),
    ]));

    expect(
      result.artifactWasUsed,
      isTrue,
      reason: 'the older artifact was discovered in the same query and is '
          'usable; giving up on the newest costs the sync the whole range',
    );
    expect(result.coveredThroughBlock, 800);
  });
}

void _swallow(DriveStateLogLevel level, String message) {}

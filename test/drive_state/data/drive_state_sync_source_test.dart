import 'dart:typed_data';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/data/drive_state_sync_source.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

/// The composer's whole job is the seam between three layers that each refuse
/// to make a decision, so these tests are about decisions: which failures get
/// an outcome, which get a note, how many lines a drive produces, and what the
/// sync above is told about the range.
///
/// The layers themselves are tested where they live. Everything below this
/// line is a stand-in for one, so that a failure here can only be the
/// composition.
class _MockImporter extends Mock implements DriveStateImporter {}

class _FakeCandidate extends Fake implements DriveStateArtifactCandidate {}

/// Discovery that answers with whatever it was given, and remembers being
/// asked. The flag-off test in the sync lane turns on `calls` being empty; the
/// tests here turn on what was in them.
class _SpyDiscovery implements DriveStateDiscovery {
  _SpyDiscovery(this._answer);

  final DriveStateDiscoveryResult Function() _answer;
  final calls =
      <({String driveId, String ownerAddress, int? minBlockHeight})>[];

  @override
  Future<DriveStateDiscoveryResult> findCandidates({
    required String driveId,
    required String ownerAddress,
    int? minBlockHeight,
  }) async {
    calls.add((
      driveId: driveId,
      ownerAddress: ownerAddress,
      minBlockHeight: minBlockHeight,
    ));
    return _answer();
  }
}

void main() {
  const driveId = 'drive-id';
  const ownerAddress = 'owner-address';
  const txId = 'artifact-tx-id';

  final driveKey = SecretKey(List.filled(32, 7));
  final body = Uint8List.fromList([1, 2, 3]);

  late MockArweaveService arweave;
  late _MockImporter importer;

  /// Every line the reporter would have written, in order, so a test can count
  /// them as well as read them.
  late List<({DriveStateLogLevel level, String message})> logged;

  setUpAll(() {
    registerFallbackValue(_FakeCandidate());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(SecretKey(const []));
  });

  setUp(() {
    arweave = MockArweaveService();
    importer = _MockImporter();
    logged = [];

    when(() => arweave.getEntityDataFromNetwork(
          txId: any(named: 'txId'),
          largeBody: any(named: 'largeBody'),
        )).thenAnswer((_) async => body);
  });

  DriveStateArtifactCandidate candidate({
    int blockStart = 0,
    int? blockEnd = 900,
    int entityCount = 3,
  }) =>
      DriveStateArtifactCandidate(
        txId: txId,
        ownerAddress: ownerAddress,
        tags: {
          EntityTag.entityType: EntityTypeTag.driveState,
          EntityTag.driveId: driveId,
          EntityTag.stateVersion: '1',
          EntityTag.blockStart: '$blockStart',
          if (blockEnd != null) EntityTag.blockEnd: '$blockEnd',
          EntityTag.entityCount: '$entityCount',
        },
      );

  DriveStateSyncSource sourceFor(
    DriveStateDiscovery discovery,
  ) =>
      DriveStateSyncSource(
        arweave: arweave,
        discovery: discovery,
        importer: importer,
        reporter: DriveStateOutcomeReporter(
          sink: (level, message) => logged.add((
            level: level,
            message: message,
          )),
        ),
      );

  Future<DriveStateSyncResult> read(
    DriveStateDiscovery discovery, {
    int lastBlockHeight = 100,
  }) =>
      sourceFor(discovery).read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        driveKey: driveKey,
        lastBlockHeight: lastBlockHeight,
      );

  /// The lines that are outcomes, as §7 defines them: exactly the three
  /// sentences [DriveStateOutcomeReporter] opens a report with. Notes are
  /// deliberately worded to match none of them, which is what makes this
  /// countable.
  List<String> outcomeLines() => logged
      .map((l) => l.message)
      .where((m) =>
          m.contains('artifact used') ||
          m.contains('no artifact was used') ||
          m.contains('artifact rejected'))
      .toList();

  void expectExactlyOneOutcome(DriveStateOutcome outcome) {
    final lines = outcomeLines();
    expect(lines, hasLength(1), reason: 'logged: $logged');
    expect(lines.single, contains('outcome=${outcome.code}'));
  }

  _SpyDiscovery found(DriveStateArtifactCandidate c) =>
      _SpyDiscovery(() => DriveStateDiscoveryResult(candidates: [c]));

  void stubImport(DriveStateImportResult result) {
    when(() => importer.import(
          candidate: any(named: 'candidate'),
          body: any(named: 'body'),
          driveKey: any(named: 'driveKey'),
          expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
        )).thenAnswer((_) async => result);
  }

  DriveStateImportResult importedThrough(int watermark) =>
      DriveStateImportResult.imported(DriveStateImportStats(
        foldersWritten: 2,
        filesWritten: 1,
        rowsKeptLocallyNewer: 0,
        watermark: watermark,
        parseDuration: const Duration(milliseconds: 4),
        mergeDuration: const Duration(milliseconds: 9),
      ));

  group('an artifact that imports', () {
    test('reports it used, once, and hands back the range it covered',
        () async {
      stubImport(importedThrough(900));

      final result = await read(found(candidate(blockEnd: 900)));

      expect(result.artifactWasUsed, isTrue);
      expect(result.coveredThroughBlock, 900);
      expect(result.covered.rangeSegments.single.start, 0);
      expect(result.covered.rangeSegments.single.end, 900);
      expectExactlyOneOutcome(DriveStateOutcome.used);
    });

    test('takes the coverage from the tags, not from `Block-Start` assumed 0',
        () async {
      // Every artifact this client publishes starts at 0 (§3.4), but that is a
      // v1 policy rather than a property of the format, and a caller that
      // assumed it would obscure a range no artifact covered.
      stubImport(importedThrough(900));

      final result = await read(found(candidate(blockStart: 500)));

      expect(result.covered.rangeSegments.single.start, 500);
    });

    test('obscures nothing when the import found a gap below the artifact',
        () async {
      // The importer refuses to move a watermark over ground nobody synced,
      // and says so by handing back the watermark it started with. The rows
      // still landed; the range they came from is still this sync's to walk,
      // and a caller that obscured it anyway would skip the gap for good.
      stubImport(importedThrough(100));

      final result = await read(
        found(candidate(blockStart: 1200, blockEnd: 1500)),
        lastBlockHeight: 100,
      );

      expect(result.artifactWasUsed, isTrue);
      expect(result.covered.rangeSegments, isEmpty);
      expect(result.coveredThroughBlock, 0);
      expectExactlyOneOutcome(DriveStateOutcome.used);
    });

    test('carries the importer\'s measurements into the line §7 asks for',
        () async {
      stubImport(importedThrough(900));

      await read(found(candidate()));

      expect(outcomeLines().single, contains('imported=3'));
      expect(outcomeLines().single, contains('parse=4ms'));
      expect(outcomeLines().single, contains('merge=9ms'));
      expect(outcomeLines().single, contains('tx=$txId'));
    });

    test('fetches the body through the gateway seam, with a large-body budget',
        () async {
      stubImport(importedThrough(900));

      await read(found(candidate()));

      verify(() => arweave.getEntityDataFromNetwork(
            txId: txId,
            largeBody: true,
          )).called(1);
    });
  });

  group('an artifact that does not import', () {
    for (final outcome in [
      DriveStateOutcome.decryptFailed,
      DriveStateOutcome.countMismatch,
      DriveStateOutcome.signatureFailed,
      DriveStateOutcome.unknownVersion,
      DriveStateOutcome.integrityFailed,
    ]) {
      test('reports ${outcome.code} once and covers nothing', () async {
        stubImport(DriveStateImportResult.rejected(outcome, 'the reason'));

        final result = await read(found(candidate()));

        expect(result.artifactWasUsed, isFalse);
        expect(result.coveredThroughBlock, 0);
        expect(result.covered.rangeSegments, isEmpty);
        expectExactlyOneOutcome(outcome);
        expect(outcomeLines().single, contains('the reason'));
      });
    }
  });

  group('nothing to import', () {
    test('reports none-found when discovery answered and found nothing',
        () async {
      final result = await read(
        _SpyDiscovery(() => const DriveStateDiscoveryResult.none()),
      );

      expect(result.coveredThroughBlock, 0);
      expectExactlyOneOutcome(DriveStateOutcome.noneFound);
      verifyNever(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          ));
    });

    test('does not claim none-found when the query was never answered',
        () async {
      // §7's rule, at its sharpest: an indexer that declined to answer has not
      // told us this drive has no artifact, and a line saying it did would be
      // a fabricated fact in the one log this feature exists to make readable.
      final result = await read(
        _SpyDiscovery(() => const DriveStateDiscoveryResult.failed()),
      );

      expect(result.coveredThroughBlock, 0);
      expect(outcomeLines(), isEmpty);
    });

    test('asks only about artifacts that could still help', () async {
      final discovery = _SpyDiscovery(
        () => const DriveStateDiscoveryResult.none(),
      );

      await read(discovery, lastBlockHeight: 1200);

      expect(discovery.calls.single.minBlockHeight, 1200);
      expect(discovery.calls.single.driveId, driveId);
      expect(discovery.calls.single.ownerAddress, ownerAddress);
    });

    test('does not filter by height for a drive that has never synced',
        () async {
      final discovery = _SpyDiscovery(
        () => const DriveStateDiscoveryResult.none(),
      );

      await read(discovery, lastBlockHeight: 0);

      expect(discovery.calls.single.minBlockHeight, isNull);
    });

    test(
        'declines an artifact below the height the sync starts from, before '
        'paying for its body', () async {
      final result = await read(
        found(candidate(blockEnd: 50)),
        lastBlockHeight: 100,
      );

      expect(result.coveredThroughBlock, 0);
      expectExactlyOneOutcome(DriveStateOutcome.rangeAlreadyCovered);
      verifyNever(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          ));
      verifyNever(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            driveKey: any(named: 'driveKey'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          ));
    });

    test('leaves an unreadable Block-End to the importer to reject', () async {
      // The early exit is an optimisation, not a rule. A tag that cannot be
      // parsed is a verdict, and verdicts belong to the layer that checks the
      // payload against them.
      stubImport(const DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'a required tag is missing',
      ));

      await read(found(candidate(blockEnd: null)));

      expectExactlyOneOutcome(DriveStateOutcome.integrityFailed);
    });
  });

  group('a failure that is not about the artifact', () {
    test('notes an unfetchable body without claiming an outcome for it',
        () async {
      when(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          )).thenThrow(Exception('gateway is down'));

      final result = await read(found(candidate()));

      expect(result.coveredThroughBlock, 0);
      expect(outcomeLines(), isEmpty);
      expect(logged, hasLength(1));
      expect(logged.single.level, DriveStateLogLevel.warning);
      expect(logged.single.message, contains('could not be fetched'));
      verifyNever(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            driveKey: any(named: 'driveKey'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          ));
    });
  });

  group('the outer net', () {
    test('swallows a discovery that throws, and still reports once', () async {
      final result = await read(
        _SpyDiscovery(() => throw StateError('discovery exploded')),
      );

      expect(result.coveredThroughBlock, 0);
      expectExactlyOneOutcome(DriveStateOutcome.integrityFailed);
      expect(outcomeLines().single, contains('threw'));
    });

    test('swallows an importer that throws, and still reports once', () async {
      when(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            driveKey: any(named: 'driveKey'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          )).thenThrow(StateError('the database went away'));

      final result = await read(found(candidate()));

      expect(result.coveredThroughBlock, 0);
      expectExactlyOneOutcome(DriveStateOutcome.integrityFailed);
    });
  });
}

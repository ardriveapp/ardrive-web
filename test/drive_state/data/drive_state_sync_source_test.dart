import 'dart:typed_data';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/data/drive_state_sync_source.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
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

  /// Resolved rather than fabricated: `DriveStateProtection` has no public
  /// constructor, which is the whole point of it.
  final privateDrive = DriveStateProtection.forDrive(
    privacy: DrivePrivacyTag.private,
    driveKey: driveKey,
  ).protection!;
  final publicDrive = DriveStateProtection.forDrive(
    privacy: DrivePrivacyTag.public,
    driveKey: null,
  ).protection!;
  final body = Uint8List.fromList([1, 2, 3]);

  late MockArweaveService arweave;
  late _MockImporter importer;

  /// Every line the reporter would have written, in order, so a test can count
  /// them as well as read them.
  late List<({DriveStateLogLevel level, String message})> logged;

  setUpAll(() {
    registerFallbackValue(_FakeCandidate());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(publicDrive);
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
    String id = txId,
  }) =>
      DriveStateArtifactCandidate(
        txId: id,
        ownerAddress: ownerAddress,
        tags: {
          EntityTag.entityType: EntityTypeTag.driveState,
          EntityTag.driveId: driveId,
          EntityTag.stateVersion: '1.0',
          EntityTag.blockStart: '$blockStart',
          if (blockEnd != null) EntityTag.blockEnd: '$blockEnd',
          EntityTag.entityCount: '$entityCount',
        },
      );

  DriveStateSyncSource sourceFor(
    DriveStateDiscovery discovery, {
    int? maxCandidateAttempts,
  }) =>
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
        maxCandidateAttempts: maxCandidateAttempts ??
            DriveStateSyncSource.defaultMaxCandidateAttempts,
      );

  Future<DriveStateSyncResult> read(
    DriveStateDiscovery discovery, {
    int lastBlockHeight = 100,
    int? maxCandidateAttempts,
  }) =>
      sourceFor(discovery, maxCandidateAttempts: maxCandidateAttempts).read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        protection: privateDrive,
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
          protection: any(named: 'protection'),
          expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
        )).thenAnswer((_) async => result);
  }

  DriveStateImportResult importedThrough(int watermark) =>
      DriveStateImportResult.imported(DriveStateImportStats(
        foldersWritten: 2,
        filesWritten: 1,
        revisionsWritten: 3,
        licensesWritten: 0,
        transactionsWritten: 5,
        rowsKeptLocallyNewer: 0,
        watermark: watermark,
        parseDuration: const Duration(milliseconds: 4),
        mergeDuration: const Duration(milliseconds: 9),
      ));

  /// The composer takes no view on privacy. It carries the protection its
  /// caller resolved from the drive row down to the importer, which is the
  /// layer that checks it against the artifact's tags — so what these assert
  /// is that the value arrives intact rather than being re-derived here.
  group('the protection is carried, not decided', () {
    test('a public drive reaches the importer as a public drive', () async {
      stubImport(importedThrough(900));

      final result = await sourceFor(found(candidate(blockEnd: 900))).read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        protection: publicDrive,
        lastBlockHeight: 100,
      );

      expect(result.artifactWasUsed, isTrue, reason: result.detail);

      final captured = verify(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            protection: captureAny(named: 'protection'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          )).captured;

      expect(captured.single, same(publicDrive));
    });

    test('a private drive reaches the importer as a private drive', () async {
      stubImport(importedThrough(900));

      await read(found(candidate(blockEnd: 900)));

      final captured = verify(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            protection: captureAny(named: 'protection'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          )).captured;

      expect(captured.single, same(privateDrive));
    });

    test('a privacy mismatch from the importer is one ordinary rejection',
        () async {
      stubImport(const DriveStateImportResult.rejected(
        DriveStateOutcome.privacyMismatch,
        'drive drive-id is private and artifact-tx-id carries no Cipher tag',
      ));

      final result = await read(found(candidate(blockEnd: 900)));

      // A fallback like every other: no range covered, one verdict, and the
      // sync below walks the whole thing itself.
      expect(result.artifactWasUsed, isFalse);
      expect(result.covered.rangeSegments, isEmpty);
      expectExactlyOneOutcome(DriveStateOutcome.privacyMismatch);
    });
  });

  /// Measured on a 41,767 file drive: re-importing the same artifact costs a
  /// 9.55 MiB download, ~173,000 statements and about 8.5 seconds, and writes
  /// zero rows. A successful import leaves `Block-End` and the watermark
  /// *equal*, and the no-rollback guard refuses only `Block-End < watermark`,
  /// so nothing stopped the next sync repeating all of it on the `autoSync`
  /// interval, forever.
  ///
  /// These reuse one source across two `read`s on purpose — the record is per
  /// session, and a fresh source per sync is exactly what would defeat it.
  group('an artifact this session already imported', () {
    test('is not fetched or imported a second time', () async {
      final source = sourceFor(found(candidate(blockEnd: 900)));
      stubImport(importedThrough(900));

      final first = await source.read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        protection: privateDrive,
        lastBlockHeight: 100,
      );
      expect(first.artifactWasUsed, isTrue, reason: first.detail);

      logged.clear();
      // The first read fetched and imported legitimately; `verifyNever` counts
      // every call ever made, so the second sync is what these must be about.
      clearInteractions(arweave);
      clearInteractions(importer);

      final second = await source.read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        protection: privateDrive,
        // What the drive's watermark is after the first import: equal to
        // Block-End, which is why the range guard does not catch this.
        lastBlockHeight: 900,
      );

      expect(second.outcome, DriveStateOutcome.rangeAlreadyCovered);
      expectExactlyOneOutcome(DriveStateOutcome.rangeAlreadyCovered);

      // The download is the expensive half, and it must not happen at all.
      verifyNever(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          ));
      verifyNever(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            protection: any(named: 'protection'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          ));
    });

    /// The distinction that makes this a check on identity and not on range.
    /// An artifact covering ground the drive already holds can still carry
    /// entities *this consumer's* sync skipped, and importing it is how those
    /// are repaired — so a different artifact at the same height is still
    /// worth reading. Widening the importer's guard to `<=` would lose that;
    /// this does not.
    test('does not block a different artifact at the same height', () async {
      var current = candidate(blockEnd: 900);
      final source = sourceFor(_SpyDiscovery(
        () => DriveStateDiscoveryResult(candidates: [current]),
      ));
      stubImport(importedThrough(900));

      await source.read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        protection: privateDrive,
        lastBlockHeight: 100,
      );

      current = candidate(blockEnd: 900, id: 'a-different-artifact');
      logged.clear();

      final second = await source.read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        protection: privateDrive,
        lastBlockHeight: 900,
      );

      expect(second.artifactWasUsed, isTrue, reason: second.detail);
    });

    test('is not remembered when the import did not succeed', () async {
      final source = sourceFor(found(candidate(blockEnd: 900)));
      stubImport(const DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'a bad day at the gateway',
      ));

      await source.read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        protection: privateDrive,
        lastBlockHeight: 100,
      );

      // Next sync the gateway may answer differently, so it must be retried.
      stubImport(importedThrough(900));
      final second = await source.read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        protection: privateDrive,
        lastBlockHeight: 100,
      );

      expect(second.artifactWasUsed, isTrue, reason: second.detail);
    });
  });

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
            protection: any(named: 'protection'),
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

  group('an artifact that was found but could not be read', () {
    /// A verdict rather than a bare note, and the distinction is §7's: the
    /// artifact is identified by transaction id, so this is a fact about that
    /// artifact. Only "the indexer never answered" stays outside the
    /// vocabulary, because there is nothing there to have a verdict about.
    test('reports fetchFailed, naming the artifact it failed on', () async {
      when(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          )).thenThrow(Exception('gateway is down'));

      final result = await read(found(candidate()));

      expect(result.coveredThroughBlock, 0);
      expectExactlyOneOutcome(DriveStateOutcome.fetchFailed);
      expect(outcomeLines().single, contains(txId));
      expect(outcomeLines().single, contains('gateway is down'));
      verifyNever(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            protection: any(named: 'protection'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          ));
    });

    test('is a fault, so it is logged loudly enough to be seen', () async {
      when(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          )).thenThrow(Exception('gateway is down'));

      await read(found(candidate()));

      expect(DriveStateOutcome.fetchFailed.isFault, isTrue);
      expect(logged.single.level, DriveStateLogLevel.warning);
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
            protection: any(named: 'protection'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          )).thenThrow(StateError('the database went away'));

      final result = await read(found(candidate()));

      expect(result.coveredThroughBlock, 0);
      expectExactlyOneOutcome(DriveStateOutcome.integrityFailed);
    });
  });

  /// Discovery returns an ordered list and this walks it. Until it did, the
  /// newest candidate failing ended the attempt and discarded artifacts the
  /// same query had already found and ordered — which closed the feature for
  /// the drive during the window every publication opens, where the newest is
  /// indexed but not yet retrievable.
  ///
  /// The properties that keep the walk honest are as much about §7 as about
  /// fallback: a drive still gets exactly one verdict, and the verdict is the
  /// one belonging to the candidate that actually decided the sync.
  group('more than one candidate', () {
    _SpyDiscovery foundAll(List<DriveStateArtifactCandidate> cs) =>
        _SpyDiscovery(() => DriveStateDiscoveryResult(candidates: cs));

    /// Newest first, as `GraphQLDriveStateDiscovery` sorts them.
    List<DriveStateArtifactCandidate> ordered(List<(String, int)> spec) => [
          for (final (id, blockEnd) in spec)
            candidate(id: id, blockEnd: blockEnd),
        ];

    void fetchFails(String id, [String reason = '404 from the gateway']) {
      when(() => arweave.getEntityDataFromNetwork(
            txId: id,
            largeBody: any(named: 'largeBody'),
          )).thenThrow(Exception(reason));
    }

    void fetchSucceeds(String id) {
      when(() => arweave.getEntityDataFromNetwork(
            txId: id,
            largeBody: any(named: 'largeBody'),
          )).thenAnswer((_) async => body);
    }

    /// Every transaction id a body was asked for, in order.
    List<String> fetched() {
      final captured = verify(() => arweave.getEntityDataFromNetwork(
            txId: captureAny(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          )).captured;
      return captured.cast<String>();
    }

    setUp(() => stubImport(importedThrough(800)));

    test('falls back to the next one when the newest cannot be fetched',
        () async {
      fetchFails('newest');
      fetchSucceeds('older');

      final result = await read(foundAll(ordered([
        ('newest', 900),
        ('older', 800),
      ])));

      expect(result.artifactWasUsed, isTrue);
      expect(result.coveredThroughBlock, 800);
      expect(fetched(), ['newest', 'older']);
    });

    test('falls back when the newest is fetched but will not verify', () async {
      // Not only unreachable bodies. An artifact that decrypts to nothing
      // usable is just as permanent a block on the feature, and the older one
      // beneath it is just as good.
      when(() => importer.import(
            candidate: any(named: 'candidate'),
            body: any(named: 'body'),
            protection: any(named: 'protection'),
            expectedOwnerAddress: any(named: 'expectedOwnerAddress'),
          )).thenAnswer((invocation) async {
        final c = invocation.namedArguments[#candidate]
            as DriveStateArtifactCandidate;
        return c.txId == 'newest'
            ? const DriveStateImportResult.rejected(
                DriveStateOutcome.signatureFailed,
                'the payload was not signed by the owner',
              )
            : importedThrough(800);
      });

      final result = await read(foundAll(ordered([
        ('newest', 900),
        ('older', 800),
      ])));

      expect(result.artifactWasUsed, isTrue);
      expect(result.coveredThroughBlock, 800);
    });

    test('reports one verdict, and it belongs to the artifact that decided',
        () async {
      fetchFails('newest');
      fetchSucceeds('older');

      await read(foundAll(ordered([
        ('newest', 900),
        ('older', 800),
      ])));

      expectExactlyOneOutcome(DriveStateOutcome.used);
      expect(outcomeLines().single, contains('tx=older'));
      expect(
        outcomeLines().single,
        isNot(contains('tx=newest')),
        reason: 'the used artifact is `older`; naming the one that failed in '
            'the same line makes "artifact used - tx=..." unreadable',
      );
    });

    test('says in that verdict how many candidates it took', () async {
      fetchFails('newest');
      fetchSucceeds('older');

      await read(foundAll(ordered([
        ('newest', 900),
        ('older', 800),
        ('oldest', 700),
      ])));

      expect(outcomeLines().single, contains('after 2 of 3 candidate(s)'));
    });

    test('leaves the discarded ones as notes, not as second verdicts',
        () async {
      // §7's rule is countable: a consumer counting `artifact rejected` lines
      // to find drives that could not use an artifact must not see this drive,
      // because it used one.
      fetchFails('newest', 'not seeded yet');
      fetchSucceeds('older');

      await read(foundAll(ordered([
        ('newest', 900),
        ('older', 800),
      ])));

      expect(outcomeLines(), hasLength(1));

      final notes = logged
          .map((l) => l.message)
          .where((m) => !outcomeLines().contains(m))
          .toList();
      expect(notes, hasLength(1));
      expect(notes.single, contains('tx=newest'));
      expect(notes.single, contains('fetch-failed'));
      expect(notes.single, contains('not seeded yet'));
    });

    test('stops after the attempt budget, however many were discovered',
        () async {
      // Each attempt is a download sized like a snapshot. A drive with a long
      // history of unusable artifacts must not be able to make a sync pay for
      // all of them.
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        fetchFails(id);
      }

      final result = await read(foundAll(ordered([
        ('a', 900),
        ('b', 890),
        ('c', 880),
        ('d', 870),
        ('e', 860),
      ])));

      expect(fetched(), ['a', 'b', 'c']);
      expect(result.artifactWasUsed, isFalse);
      expectExactlyOneOutcome(DriveStateOutcome.fetchFailed);
      expect(outcomeLines().single, contains('after 3 of 5 candidate(s)'));
    });

    test('the budget is what bounds it, not the number discovered', () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        fetchFails(id);
      }

      await read(
        foundAll(ordered([('a', 900), ('b', 890), ('c', 880), ('d', 870)])),
        maxCandidateAttempts: 2,
      );

      expect(fetched(), ['a', 'b']);
    });

    test(
        'an already-covered candidate ends the walk rather than being '
        'skipped over', () async {
      // The list is ordered by `Block-End` descending, so a candidate at or
      // below the local watermark guarantees every candidate after it is too.
      // `rangeAlreadyCovered` is an early exit, not a failure, and treating it
      // as one more reason to try the next one turns the cheapest path there
      // is into the most expensive.
      final result = await read(
        foundAll(ordered([
          ('covered', 50),
          ('even-older', 40),
        ])),
        lastBlockHeight: 100,
      );

      expect(result.artifactWasUsed, isFalse);
      expectExactlyOneOutcome(DriveStateOutcome.rangeAlreadyCovered);
      expect(
        logged,
        hasLength(1),
        reason: 'the walk stopped at the first covered candidate, so there is '
            'nothing else it discarded to note: $logged',
      );
      expect(outcomeLines().single, isNot(contains('candidate(s)')));
      verifyNever(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          ));
    });

    test('and does not go on to pay for one it cannot rule out cheaply',
        () async {
      // `_newestFirst` sorts a candidate with no parseable `Block-End` last
      // rather than dropping it, and the cheap coverage check cannot rule that
      // one out — so it is the candidate a walk that did not stop would
      // download. This is where continuing past an early exit actually costs
      // money.
      stubImport(const DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'a required tag is missing',
      ));

      await read(
        foundAll([
          candidate(id: 'covered', blockEnd: 50),
          candidate(id: 'unparseable', blockEnd: null),
        ]),
        lastBlockHeight: 100,
      );

      expectExactlyOneOutcome(DriveStateOutcome.rangeAlreadyCovered);
      verifyNever(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          ));
    });

    test('a usable newest one costs nothing extra', () async {
      fetchSucceeds('newest');

      final result = await read(foundAll(ordered([
        ('newest', 900),
        ('older', 800),
      ])));

      expect(result.artifactWasUsed, isTrue);
      expect(fetched(), ['newest']);
      expectExactlyOneOutcome(DriveStateOutcome.used);
      expect(
        outcomeLines().single,
        isNot(contains('candidate(s)')),
        reason: 'nothing was walked, so there is no walk to describe',
      );
    });
  });
}

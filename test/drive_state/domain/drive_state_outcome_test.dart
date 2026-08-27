import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// The observability contract from `docs/DRIVE_STATE_ARTIFACT.md` §7. These
/// tests are the enforcement of one sentence:
///
/// > "no artifact was used" and "an artifact was rejected because X" must
/// > never look the same.
///
/// They assert on the exact text because the text is the interface — someone
/// reading an exported log, or grepping one, is the consumer.
void main() {
  const driveId = 'e93cf9c4-5f20-4d7a-87c1-2e0ba1b0b7a1';

  /// Every phrase a reader would grep for, and the one kind it may match.
  const kindPhrases = {
    DriveStateOutcomeKind.used: 'artifact used',
    DriveStateOutcomeKind.nothingFound: 'no artifact was used',
    DriveStateOutcomeKind.rejected: 'artifact rejected',
  };

  String lineFor(DriveStateOutcome outcome, {String? txId, String? detail}) =>
      DriveStateOutcomeReporter.formatLine(
        driveId: driveId,
        outcome: outcome,
        txId: txId,
        detail: detail,
      );

  group('DriveStateOutcome vocabulary', () {
    test('covers exactly the outcomes §7 enumerates', () {
      expect(
        DriveStateOutcome.values.map((o) => o.code).toSet(),
        {
          'used',
          'none-found',
          'unknown-version',
          'signature-failed',
          'decrypt-failed',
          'integrity-failed',
          'count-mismatch',
          'coverage-mismatch',
          // The cipher/privacy cross-check (§2.6), in both directions. Its own
          // code rather than a shade of `integrity-failed`, for the reason
          // `coverage-mismatch` has one: a private drive being offered an
          // artifact in the clear is not a damaged payload, it is a producer
          // having published the thing this design most exists to prevent.
          'privacy-mismatch',
          'fetch-failed',
          'range-already-covered',
        },
      );
    });

    test('gives every outcome a unique code', () {
      final codes = DriveStateOutcome.values.map((o) => o.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
    });

    test('classifies "nothing found" apart from every rejection', () {
      expect(
          DriveStateOutcome.noneFound.kind, DriveStateOutcomeKind.nothingFound);
      expect(DriveStateOutcome.used.kind, DriveStateOutcomeKind.used);

      final rejections = DriveStateOutcome.values
          .where((o) => o != DriveStateOutcome.used)
          .where((o) => o != DriveStateOutcome.noneFound);
      for (final outcome in rejections) {
        expect(outcome.kind, DriveStateOutcomeKind.rejected,
            reason: '${outcome.name} describes an artifact that was found');
      }
    });

    test('only a fault raises the log level', () {
      expect(DriveStateOutcomeReporter.levelFor(DriveStateOutcome.used),
          DriveStateLogLevel.info);
      expect(DriveStateOutcomeReporter.levelFor(DriveStateOutcome.noneFound),
          DriveStateLogLevel.info);
      // Found, and declined because reading it would change nothing. Nobody's
      // fault, so it must not read like a problem.
      expect(
        DriveStateOutcomeReporter.levelFor(
            DriveStateOutcome.rangeAlreadyCovered),
        DriveStateLogLevel.info,
      );

      for (final outcome in [
        DriveStateOutcome.unknownVersion,
        DriveStateOutcome.signatureFailed,
        DriveStateOutcome.decryptFailed,
        DriveStateOutcome.integrityFailed,
        DriveStateOutcome.countMismatch,
        DriveStateOutcome.coverageMismatch,
      ]) {
        expect(DriveStateOutcomeReporter.levelFor(outcome),
            DriveStateLogLevel.warning,
            reason: '${outcome.name} means an artifact was there and unusable');
      }
    });
  });

  group('log lines', () {
    test('every outcome produces a distinct line', () {
      final lines = DriveStateOutcome.values.map(lineFor).toList();
      expect(lines.toSet(), hasLength(DriveStateOutcome.values.length));
    });

    test('every line is greppable by prefix and by an exact outcome token', () {
      for (final outcome in DriveStateOutcome.values) {
        final line = lineFor(outcome);
        expect(line, contains('[drive-state]'));
        expect(line, contains(driveId));
        expect(line, contains('outcome=${outcome.code}'));
      }
    });

    test('an outcome token matches that outcome and no other', () {
      for (final outcome in DriveStateOutcome.values) {
        final token = 'outcome=${outcome.code}';
        final matches = DriveStateOutcome.values
            .where((other) => lineFor(other).contains(token))
            .toList();
        expect(matches, [outcome],
            reason: '"$token" must identify exactly one outcome');
      }
    });

    test('"no artifact was used" and "artifact rejected" never collide', () {
      for (final outcome in DriveStateOutcome.values) {
        final line = lineFor(outcome);
        final expectedPhrase = kindPhrases[outcome.kind]!;

        expect(line, contains(expectedPhrase));

        for (final entry in kindPhrases.entries) {
          if (entry.key == outcome.kind) continue;
          expect(line, isNot(contains(entry.value)),
              reason: '${outcome.name} must not read as ${entry.key.name}');
        }
      }
    });

    test('carries the transaction id and any extra detail when given', () {
      final line = lineFor(
        DriveStateOutcome.countMismatch,
        txId: 'TX_ID_1',
        detail: 'declared=1200 imported=1199',
      );

      expect(line, contains('tx=TX_ID_1'));
      expect(line, contains('declared=1200 imported=1199'));
      expect(line, contains('outcome=count-mismatch'));
    });

    test('omits the transaction id when there was never an artifact', () {
      expect(lineFor(DriveStateOutcome.noneFound), isNot(contains('tx=')));
    });
  });

  group('DriveStateOutcomeReporter', () {
    test('reports each outcome once, at the level for that outcome', () {
      final captured = <(DriveStateLogLevel, String)>[];
      final reporter = DriveStateOutcomeReporter(
        sink: (level, message) => captured.add((level, message)),
      );

      for (final outcome in DriveStateOutcome.values) {
        reporter.report(driveId: driveId, outcome: outcome, txId: 'TX');
      }

      expect(captured, hasLength(DriveStateOutcome.values.length));
      for (var i = 0; i < DriveStateOutcome.values.length; i++) {
        final outcome = DriveStateOutcome.values[i];
        expect(captured[i].$1, DriveStateOutcomeReporter.levelFor(outcome));
        expect(captured[i].$2, contains('outcome=${outcome.code}'));
      }
    });

    test('a note is not mistaken for an outcome', () {
      final captured = <String>[];
      DriveStateOutcomeReporter(sink: (_, message) => captured.add(message))
          .note(driveId: driveId, message: 'discovery found 0 candidate(s)');

      expect(captured.single, startsWith('[drive-state] $driveId: '));
      for (final phrase in kindPhrases.values) {
        expect(captured.single, isNot(contains(phrase)));
      }
      expect(captured.single, isNot(contains('outcome=')));
    });

    test('the default reporter writes through the app logger', () {
      // The exported log is where this actually gets read, so check the line
      // survives the real logger rather than only the injected sink.
      logger.inMemoryLogs.clear();

      const DriveStateOutcomeReporter().report(
        driveId: driveId,
        outcome: DriveStateOutcome.signatureFailed,
        txId: 'TX_ID_2',
      );

      expect(
        logger.inMemoryLogs.where(
          (line) => line.contains('outcome=signature-failed'),
        ),
        hasLength(1),
      );
    });
  });
}

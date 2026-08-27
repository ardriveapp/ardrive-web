import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// `uploadTx` has to be able to say whether the transaction reached the
/// network, because its caller cannot tell otherwise: a refused header and a
/// chunk that failed on its fifteenth attempt arrive as the same exception,
/// and only one of them cost the user anything.
///
/// `TransactionUploader.upload` (arweave-dart v4.0.2, the pinned ref) awaits
/// `_postTransactionHeader()` and only then yields its first event; every
/// later event is a completed chunk. So the first event is the signal, and a
/// stream that errors before yielding anything is a transaction that was
/// never posted.
///
/// [ArweaveService.drainUpload] is that rule on its own. It is exercised here
/// rather than through `uploadTx` because `ArweaveTransactionsApi` is not
/// exported by `package:arweave`, so the client's uploader cannot be mocked —
/// and it must be mocked, because the real one spends money.
void main() {
  test('reports the transaction as posted on the first event', () async {
    var posted = 0;

    await ArweaveService.drainUpload(
      Stream.fromIterable(const ['header', 'chunk 0', 'chunk 1']),
      dryRun: false,
      onTransactionPosted: () => posted++,
    );

    expect(
      posted,
      1,
      reason: 'the header is posted once, before the chunks; every event '
          'after the first is a chunk that completed',
    );
  });

  test('does not report a transaction the network never accepted', () async {
    // The header post is retried inside the uploader and then gives up by
    // throwing, without ever yielding. Nothing was posted, so nothing was
    // spent, and the caller must stay free to say so.
    var posted = false;

    await expectLater(
      ArweaveService.drainUpload(
        Stream<Object?>.error(Exception('unable to upload transaction: 503')),
        dryRun: false,
        onTransactionPosted: () => posted = true,
      ),
      throwsA(isA<Exception>()),
    );

    expect(posted, isFalse);
  });

  test('reports a transaction posted before a later chunk failed', () async {
    // The case the callback exists for: the transaction is on the network and
    // will be charged for, and then the upload dies part-way through its data.
    var posted = false;

    await expectLater(
      ArweaveService.drainUpload(
        () async* {
          yield 'header';
          throw Exception('chunk 41 rejected after fifteen attempts');
        }(),
        dryRun: false,
        onTransactionPosted: () => posted = true,
      ),
      throwsA(isA<Exception>()),
    );

    expect(
      posted,
      isTrue,
      reason: 'this is the failure that must not be reported as free',
    );
  });

  test('a dry run posts nothing, so it reports nothing', () async {
    // `upload` yields the uploader without posting when asked for a dry run.
    // Reporting that as a posted transaction would invent a charge.
    var posted = false;

    await ArweaveService.drainUpload(
      Stream.fromIterable(const ['the uploader, unposted']),
      dryRun: true,
      onTransactionPosted: () => posted = true,
    );

    expect(posted, isFalse);
  });
}

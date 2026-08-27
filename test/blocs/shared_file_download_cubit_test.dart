import 'dart:async';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/download/download_policy.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:cryptography/cryptography.dart';
// Arrives transitively through flutter_test, as `device_info_plus` does in
// lib/download/limits.dart.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:ardrive/services/services.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

/// A revision with a data transaction, which [MockARFSFile] cannot express.
class _Revision extends ARFSFileEntity {
  _Revision()
      : super(
          appName: 'ArDrive-App',
          appVersion: '2.86.0',
          arFS: '0.11',
          driveId: 'drive-id',
          entityType: EntityType.file,
          name: 'holiday.mp4',
          txId: 'metadata-tx',
          unixTime: DateTime.utc(2026, 8, 5),
          id: 'file-id',
          size: 5003,
          lastModifiedDate: DateTime.utc(2026, 8, 5),
          parentFolderId: 'parent-folder-id',
          contentType: 'video/mp4',
          dataTxId: 'data-tx',
        );
}

/// The size ceiling that cannot be reached.
///
/// [DownloadPolicy.singleFileLimit] asks `AppPlatform.isSafari`, which reads
/// the device info **platform channel**. A channel that is not registered - a
/// browser build where the plugin failed to load, a platform that does not
/// answer - throws, and this stands in for that.
class _UnavailablePolicy extends DownloadPolicy {
  const _UnavailablePolicy();

  @override
  Future<DownloadSizeLimit> singleFileLimit({required bool isPublic}) async {
    throw MissingPluginException(
      'No implementation found for method getDeviceInfo',
    );
  }
}

/// Records that a download was started, and lets a test drive its progress,
/// its integrity verdict and its mid-stream recoveries independently.
///
/// The three are independent in the real downloader too, which is the whole
/// reason this file exists: a verdict that arrives after the last byte must
/// still reach the screen, and must never be what the save is waiting for.
class _RecordingDownloader implements ArDriveDownloader {
  _RecordingDownloader({
    Stream<double>? progress,
    Future<DataItemIntegrityResult>? integrity,
  })  : _progress = progress ?? Stream<double>.fromIterable(const [100.0]),
        _integrity = integrity ??
            Future<DataItemIntegrityResult>.value(
              const DataItemIntegrityResult.notVerified('not under test'),
            );

  final Stream<double> _progress;
  final Future<DataItemIntegrityResult> _integrity;

  final StreamController<DownloadResumeEvent> _resumes =
      StreamController<DownloadResumeEvent>.broadcast();

  int downloadFileCalls = 0;

  /// What happened, in the order it happened. The save finishing before the
  /// verdict is read is a property, not an accident.
  final List<String> log = [];

  static const lastByteSaved = 'the last byte was saved';
  static const verdictRead = 'the verdict was read';

  /// The downloader losing its connection and picking itself back up.
  void announceResume() {
    _resumes.add(const DownloadResumeEvent(
      txId: 'data-tx',
      resumedFromBytes: 2048,
      attempt: 1,
      cause: 'the connection dropped',
    ));
  }

  /// What the cubit asked for, so a download that quietly starts depending on
  /// GraphQL again is visible from the test that cares.
  bool? lastVerifyIntegrity;

  @override
  Future<Stream<double>> downloadFile({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload = false,
    bool verifyIntegrity = false,
  }) async {
    downloadFileCalls++;
    lastVerifyIntegrity = verifyIntegrity;

    return _logged();
  }

  Stream<double> _logged() async* {
    yield* _progress;
    log.add(lastByteSaved);
  }

  @override
  Future<Uint8List> downloadToMemory({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> abortDownload() async {}

  @override
  Future<DataItemIntegrityResult> get integrity {
    log.add(verdictRead);

    return _integrity;
  }

  @override
  Stream<DownloadResumeEvent> get resumeEvents => _resumes.stream;

  Future<void> dispose() => _resumes.close();
}

/// A data transaction as GraphQL hands it over, carrying whatever tags a test
/// gives it.
///
/// `getTag` is an extension method over [TransactionCommonMixin.tags], so a
/// mock of `getTag` is never consulted - the extension reads `tags` directly.
class _FakeDataTransaction extends Fake implements TransactionCommonMixin {
  _FakeDataTransaction({Map<String, String> tags = const {}}) : _tags = tags;

  final Map<String, String> _tags;

  @override
  List<TransactionCommonMixin$Tag> get tags => _tags.entries
      .map((entry) => TransactionCommonMixin$Tag()
        ..name = entry.key
        ..value = entry.value)
      .toList();
}

/// The recipient's download.
void main() {
  SharedFileDownloadCubit cubitFor(
    _RecordingDownloader downloader, {
    ArweaveService? arweave,
    SecretKey? fileKey,
    bool publicIsUnconfirmed = false,
    String? cipher,
    String? cipherIv,
    DownloadPolicy policy = const _UnavailablePolicy(),
  }) {
    return SharedFileDownloadCubit(
      revision: _Revision(),
      arweave: arweave ?? MockArweaveService(),
      crypto: MockArDriveCrypto(),
      arDriveDownloader: downloader,
      fileKey: fileKey,
      cipher: cipher,
      cipherIv: cipherIv,
      publicIsUnconfirmed: publicIsUnconfirmed,
      downloadPolicy: policy,
    );
  }

  test(
      'a private download uses the cipher the link named, without asking for '
      'it again', () async {
    // `c` and `iv` are in the link schema precisely so this lookup does not
    // have to happen. Before this the download re-fetched tags the link had
    // already delivered - wasted on a good connection, and on a rate limited
    // one a call that can fail outright.
    final arweave = MockArweaveService();
    final downloader = _RecordingDownloader();

    final cubit = cubitFor(
      downloader,
      arweave: arweave,
      fileKey: SecretKey(List.filled(32, 1)),
      cipher: 'AES256-GCM',
      cipherIv: 'an-iv',
    );

    await cubit.stream.firstWhere((s) => s is! FileDownloadStarting);

    verifyNever(() => arweave.getTransactionDetails(any()));
  });

  /// Collects everything the cubit says, from before it says anything.
  Future<List<FileDownloadState>> observe(SharedFileDownloadCubit cubit) async {
    final seen = <FileDownloadState>[];
    final sub = cubit.stream.listen(seen.add);
    await pumpEventQueue();
    await sub.cancel();

    return seen;
  }

  test('an encrypted file with no key is refused, not saved as ciphertext',
      () async {
    // The failure this exists to stop: `file_share_cubit` resolves a private
    // file's cipher on a bounded, unawaited lookup and treats the link as
    // complete when it fails - which it does on any connection the gateway
    // rate limits. The recipient then reads a private file as public, nothing
    // decrypts, and the ciphertext is written to disk under the file's own
    // name. No step errors; the user gets a file their OS cannot open.
    final arweave = MockArweaveService();
    final downloader = _RecordingDownloader();

    when(() => arweave.getTransactionDetails(any())).thenAnswer(
      (_) async => _FakeDataTransaction(
        tags: const {EntityTag.cipher: 'AES256-GCM'},
      ),
    );

    // No key: exactly what a link that failed to declare its cipher produces.
    final seen = await observe(
      cubitFor(downloader, arweave: arweave, publicIsUnconfirmed: true),
    );

    final failures = seen.whereType<FileDownloadFailure>();
    expect(failures, isNotEmpty);
    expect(
      failures.last.reason,
      FileDownloadFailureReason.encryptedWithoutKey,
    );

    // And nothing was handed to the downloader to write.
    expect(downloader.downloadFileCalls, 0);
  });

  test('a public file is downloaded, not refused', () async {
    // The same check must not turn every public shared download into a
    // failure: a transaction with no `Cipher` tag is what public looks like.
    final arweave = MockArweaveService();
    final downloader = _RecordingDownloader();

    when(() => arweave.getTransactionDetails(any()))
        .thenAnswer((_) async => _FakeDataTransaction());

    final seen = await observe(
      cubitFor(downloader, arweave: arweave, publicIsUnconfirmed: true),
    );

    expect(seen.whereType<FileDownloadFailure>(), isEmpty);
    expect(downloader.downloadFileCalls, 1);
  });

  test('a check that cannot be made does not cost the download', () async {
    // A gateway that will not answer is not evidence of encryption, and the
    // overwhelming majority of these downloads are what they say they are.
    final arweave = MockArweaveService();
    final downloader = _RecordingDownloader();

    when(() => arweave.getTransactionDetails(any()))
        .thenThrow(Exception('gateway is unreachable'));

    final seen = await observe(
      cubitFor(downloader, arweave: arweave, publicIsUnconfirmed: true),
    );

    expect(seen.whereType<FileDownloadFailure>(), isEmpty);
    expect(downloader.downloadFileCalls, 1);
  });

  test('cancelling during the encryption check stops the download', () async {
    // The check sits between the recipient pressing Download and anything
    // happening, so it is the window most likely to be cancelled in. Nothing
    // may outlive that: neither a download started after the fact, nor a
    // failure state painted over the cancellation.
    final arweave = MockArweaveService();
    final downloader = _RecordingDownloader();
    final lookup = Completer<TransactionCommonMixin?>();

    when(() => arweave.getTransactionDetails(any()))
        .thenAnswer((_) => lookup.future);

    final cubit = cubitFor(
      downloader,
      arweave: arweave,
      publicIsUnconfirmed: true,
    );

    // Wait for the download to be sitting in the check.
    await cubit.stream.firstWhere((s) => s is FileDownloadInProgress);

    cubit.abortDownload();

    // The gateway answers late, and says the worst thing it could say.
    lookup.complete(
      _FakeDataTransaction(tags: const {EntityTag.cipher: 'AES256-GCM'}),
    );
    await pumpEventQueue();

    expect(cubit.state, isA<FileDownloadAborted>());
    expect(downloader.downloadFileCalls, 0);

    await cubit.close();
    await downloader.dispose();
  });

  test('a size check that throws costs the check, not the download', () async {
    final downloader = _RecordingDownloader();

    // The constructor starts this and discards the future, so an error that
    // escapes [verifyUploadLimitationsAndDownload] is both an unhandled
    // asynchronous error *and* a dialog that sits on "starting" for ever:
    // nothing emits, so nothing - not even `addError` - reports it.
    final cubit = cubitFor(downloader);

    await expectLater(
      cubit.stream,
      emitsInOrder(<Matcher>[
        isA<FileDownloadInProgress>(),
        isA<FileDownloadWithProgress>(),
        // No `FileDownloadVerifying`: this verdict is already settled, and a
        // step that announces itself and replaces itself in the same breath is
        // a flash of something that never happened.
        isA<FileDownloadFinishedWithSuccess>(),
      ]),
    );

    expect(downloader.downloadFileCalls, 1);

    await cubit.close();
    await downloader.dispose();
  });

  group('the integrity verdict reaches the user', () {
    // The gap this whole exercise exists to close.
    //
    // [ArDriveDownloader.integrity] has been reaching a three-valued verdict on
    // every download since Phase 2, and until now nothing read it: a file whose
    // bytes contradicted the signature that covers them was reported as
    // "Download finished!" and nothing else. A verdict nobody surfaces is
    // indistinguishable from no verdict at all, which is why this test is the
    // point of the exercise rather than a detail of it.
    test('a failed verdict lands in a state the dialog renders', () async {
      final downloader = _RecordingDownloader(
        integrity: Future<DataItemIntegrityResult>.value(
          const DataItemIntegrityResult.failed(
            'The bytes do not hash to the signed data item',
          ),
        ),
      );

      final cubit = cubitFor(downloader);

      await expectLater(
        cubit.stream,
        emitsInOrder(<Matcher>[
          isA<FileDownloadInProgress>(),
          isA<FileDownloadWithProgress>(),
          isA<FileDownloadFinishedWithSuccess>()
              .having(
                (s) => s.integrity,
                'integrity',
                DataItemIntegrityVerdict.failed,
              )
              .having((s) => s.fileName, 'fileName', 'holiday.mp4'),
        ]),
      );

      await cubit.close();
      await downloader.dispose();
    });

    test('a verified verdict is carried through as well', () async {
      final downloader = _RecordingDownloader(
        integrity: Future<DataItemIntegrityResult>.value(
          const DataItemIntegrityResult.verified(bytesHashed: 5003),
        ),
      );

      final cubit = cubitFor(downloader);

      await expectLater(
        cubit.stream,
        emitsThrough(
          isA<FileDownloadFinishedWithSuccess>().having(
            (s) => s.integrity,
            'integrity',
            DataItemIntegrityVerdict.verified,
          ),
        ),
      );

      await cubit.close();
      await downloader.dispose();
    });

    test(
        'a verdict that never arrives does not trap the download in '
        '"checking"', () {
      // [ArDriveDownloader.integrity] is documented to always complete, and
      // every path in the downloader settles it. The dialog is a
      // `barrierDismissible: false` modal with nothing to press while it is
      // checking, so the one time that guarantee is missed must not leave a
      // user watching a spinner over a file that is already on disk.
      fakeAsync((async) {
        final downloader = _RecordingDownloader(
          integrity: Completer<DataItemIntegrityResult>().future,
        );

        final cubit = cubitFor(downloader);

        final seen = <FileDownloadState>[];
        final subscription = cubit.stream.listen(seen.add);

        // Past the cubit's ceiling on the wait, without spending it.
        async.elapse(const Duration(seconds: 30));

        expect(seen, contains(isA<FileDownloadVerifying>()));
        expect(
          seen.last,
          isA<FileDownloadFinishedWithSuccess>().having(
            (s) => s.integrity,
            'integrity',
            // Never `failed`: nothing was checked, and saying otherwise about
            // a file that is probably fine is the whole thing this three
            // valued verdict exists to avoid.
            DataItemIntegrityVerdict.notVerified,
          ),
        );

        subscription.cancel();
        cubit.close();
        downloader.dispose();
        async.flushMicrotasks();
      });
    });

    test('the save never waits on the verdict', () async {
      // The property the downloader was built for and that the cubit must not
      // undo: a slow signature check cannot hold up "Saved". The only way to
      // honour it is to read [ArDriveDownloader.integrity] *after* the progress
      // stream is done, which is exactly what this ordering asserts.
      final gate = Completer<DataItemIntegrityResult>();
      final downloader = _RecordingDownloader(integrity: gate.future);

      final cubit = cubitFor(downloader);

      final seen = <FileDownloadState>[];
      final subscription = cubit.stream.listen(seen.add);

      // Past the announce delay: a verdict that really is being waited on is
      // still worth telling the user about, which is why the state was kept.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await pumpEventQueue();

      expect(seen.last, isA<FileDownloadVerifying>());
      expect(seen.whereType<FileDownloadFinishedWithSuccess>(), isEmpty);
      expect(
        downloader.log,
        [_RecordingDownloader.lastByteSaved, _RecordingDownloader.verdictRead],
      );

      gate.complete(const DataItemIntegrityResult.verified(bytesHashed: 5003));
      await pumpEventQueue();

      expect(seen.last, isA<FileDownloadFinishedWithSuccess>());

      await subscription.cancel();
      await cubit.close();
      await downloader.dispose();
    });

    test('a verdict that lands after the dialog is gone is dropped quietly',
        () async {
      final gate = Completer<DataItemIntegrityResult>();
      final downloader = _RecordingDownloader(integrity: gate.future);

      final cubit = cubitFor(downloader);

      await expectLater(
        cubit.stream,
        emitsThrough(isA<FileDownloadVerifying>()),
      );

      await cubit.close();

      // `emit` on a closed cubit throws, and this future is deliberately
      // unawaited by its caller, so it would surface as an unhandled
      // asynchronous error rather than anywhere a user could act on.
      gate.complete(const DataItemIntegrityResult.verified(bytesHashed: 5003));
      await pumpEventQueue();

      await downloader.dispose();
    });
  });

  test('a mid-stream recovery is visible instead of a frozen bar', () async {
    final progress = StreamController<double>();
    final downloader = _RecordingDownloader(progress: progress.stream);

    final cubit = cubitFor(downloader);

    final seen = <FileDownloadState>[];
    final subscription = cubit.stream.listen(seen.add);

    await pumpEventQueue();

    progress.add(62);
    await pumpEventQueue();

    // The connection drops. No bytes arrive, so no progress event does either,
    // and without this the bar simply stops - which is what a hung app looks
    // like.
    downloader.announceResume();
    await pumpEventQueue();

    progress.add(80);
    await pumpEventQueue();

    await progress.close();
    await pumpEventQueue();

    expect(
      seen
          .whereType<FileDownloadWithProgress>()
          .map((s) => '${s.progress}% reconnecting=${s.isReconnecting}'),
      [
        '62% reconnecting=false',
        // Same number, and that is the point: the download did not lose its
        // place, so neither does the bar.
        '62% reconnecting=true',
        '80% reconnecting=false',
      ],
    );

    await subscription.cancel();
    await cubit.close();
    await downloader.dispose();
  });

  test(
      'a reconnect before the first progress tick is not announced over a '
      'spinner', () async {
    // [FileDownloadInProgress] is an indeterminate spinner, which never looks
    // frozen. Only a bar that has stopped moving needs explaining.
    final progress = StreamController<double>();
    final downloader = _RecordingDownloader(progress: progress.stream);

    final cubit = cubitFor(downloader);

    final seen = <FileDownloadState>[];
    final subscription = cubit.stream.listen(seen.add);

    await pumpEventQueue();
    expect(seen.last, isA<FileDownloadInProgress>());

    downloader.announceResume();
    await pumpEventQueue();

    expect(seen.whereType<FileDownloadWithProgress>(), isEmpty);

    await progress.close();
    await pumpEventQueue();

    await subscription.cancel();
    await cubit.close();
    await downloader.dispose();
  });
}

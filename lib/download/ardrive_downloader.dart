import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/download/download_policy.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show listIntToUint8ListTransformer;
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

/// The 16 byte AES-GCM authentication tag that the uploader concatenates onto
/// the ciphertext.
const gcmMacLengthBytes = 16;

/// Decrypts a ciphertext stream that begins at [startOffsetBytes].
///
/// Defaults to [decryptTransactionDataStream]. It is injectable so that resume
/// can be exercised with an offset-sensitive stand-in in environments where
/// the WebCrypto native library is not loadable.
///
/// [gcmTooLargeToBuffer] is the caller's assertion that an AES-GCM file cannot
/// be buffered and MAC-verified; see [_ArDriveDownloader._getFileStream].
typedef PrivateStreamDecryptor = Future<Stream<Uint8List>> Function(
  String cipher,
  Uint8List cipherIv,
  Stream<Uint8List> ciphertextStream,
  Uint8List keyData,
  int fileSize, {
  int startOffsetBytes,
  bool gcmTooLargeToBuffer,
});

/// Builds the integrity checker for a transaction, or an
/// [StreamedDataItemVerifier.unavailable] one when no verdict is reachable.
typedef IntegrityVerifierFactory = Future<StreamedDataItemVerifier> Function(
    String txId);

/// The byte offset a resume must re-request from, after [delivered] bytes have
/// already reached the caller.
///
/// Encrypted streams align **down to the 16 byte AES block**: [AesStream] can
/// only seed its counter at a whole block, so at most 15 bytes are re-fetched
/// and dropped. It is *not* necessary to align to the 256 KiB chunk size — the
/// chunk grid restarts coherently from any block boundary. Plain streams
/// resume exactly where they stopped.
int resumeOffsetFor(int delivered, {required bool encrypted}) =>
    encrypted ? AesStream.alignStartOffsetDown(delivered) : delivered;

abstract class ArDriveDownloader {
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
    bool verifyDownload,
    bool verifyIntegrity,
  });
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
    bool verifyDownload,
  });
  Future<void> abortDownload();

  /// The integrity verdict for the download started by the most recent
  /// [downloadFile] call.
  ///
  /// Await it *after* the progress stream is done: saving never waits on this,
  /// so a slow signature check cannot hold up "Saved." Completes with
  /// [DataItemIntegrityVerdict.notVerified] — never with an error — whenever
  /// no verdict could be reached, which is not evidence of a problem.
  ///
  /// - AES-GCM files resolve to [DataItemIntegrityVerdict.verified] the moment
  ///   the MAC checks out, which is before a byte is written.
  /// - AES-CTR and public files resolve when the last byte has streamed
  ///   through [StreamedDataItemVerifier] - but only when the caller asked for
  ///   `verifyIntegrity`, which nothing does. Without it the verdict is
  ///   [DataItemIntegrityVerdict.notVerified], which is the honest answer for
  ///   a check that was not run and is why the dialog treats `notVerified` as
  ///   unremarkable and `failed` as the only thing worth interrupting for.
  /// - A resumed download resolves to [DataItemIntegrityVerdict.notVerified]:
  ///   the hash of the bytes before the interruption is gone.
  Future<DataItemIntegrityResult> get integrity;

  /// Emits once per mid-stream recovery, so the UI can show "Reconnecting…"
  /// instead of a frozen progress bar. A download that never stumbles emits
  /// nothing.
  Stream<DownloadResumeEvent> get resumeEvents;

  factory ArDriveDownloader({
    required IOFileAdapter ioFileAdapter,
    required ArDriveIO ardriveIo,
    required ArweaveService arweave,
    DownloadSource? source,
    PrivateStreamDecryptor? decryptStream,
    IntegrityVerifierFactory? verifierFactory,
    Duration? resumeBackoffStep,
    bool? saveTargetNeedsUserActivation,
  }) {
    // F24: no download path may decrypt AES-GCM without checking the MAC any
    // more. Disarm the class so that an accidental reuse throws instead of
    // quietly handing back unauthenticated plaintext.
    //
    // The one file that cannot obey this is one too large to hold in memory;
    // it goes through [AesGcmStream.unauthenticatedTooLargeToBuffer], which is
    // deliberately not governed by this switch and is reachable from exactly
    // one place ([_ArDriveDownloader._getFileStream]).
    AesGcmStream.allowUnauthenticatedGcmDecryption = false;

    return _ArDriveDownloader(
      ioFileAdapter,
      ardriveIo,
      arweave,
      source: source,
      decryptStream: decryptStream,
      verifierFactory: verifierFactory,
      resumeBackoffStep: resumeBackoffStep,
      saveTargetNeedsUserActivation: saveTargetNeedsUserActivation,
    );
  }
}

class _ArDriveDownloader implements ArDriveDownloader {
  final IOFileAdapter _ioFileAdapter;
  final ArDriveIO _ardriveIo;
  final ArweaveService _arweave;
  final PrivateStreamDecryptor _decryptStream;

  /// How long to wait before the nth consecutive resume attempt. Injectable so
  /// tests can prove the loop terminates without spending the wall clock on it.
  final Duration _resumeBackoffStep;

  /// Whether the saver has to be handed the file *before* its bytes exist.
  ///
  /// On the web it does. `ArDriveIO.saveFileStream` opens
  /// `window.showSaveFilePicker`
  /// (`packages/ardrive_io/lib/src/web/web_io.dart:95`) as its first act, and
  /// Chrome only allows that while the click that started the download still
  /// counts as *transient user activation* — a few seconds. A path that
  /// downloads a whole file and asks the user where to put it afterwards is
  /// rejected on a completed, verified download, which is exactly what
  /// buffering AES-GCM did to every private file on Chrome.
  ///
  /// So on the web the picker is opened on the first turn and the download
  /// runs inside [IOFile.openReadStream], which yields nothing until the MAC
  /// has passed. The cost is that the picker has already created an empty file
  /// at the chosen path by the time an integrity failure is known, so a
  /// tampered file leaves 0 bytes behind instead of nothing at all. No
  /// plaintext is ever written unauthenticated either way.
  ///
  /// Everywhere else there is no picker and no gesture to race
  /// (`DartIOFileSaver.saveStream` writes straight to the downloads
  /// directory), so nothing is opened at all until the MAC has passed and the
  /// stronger guarantee is kept.
  final bool _saveTargetNeedsUserActivation;

  late final DownloadSource _source;
  late final IntegrityVerifierFactory _verifierFactory;

  _ArDriveDownloader(
    this._ioFileAdapter,
    this._ardriveIo,
    this._arweave, {
    DownloadSource? source,
    PrivateStreamDecryptor? decryptStream,
    IntegrityVerifierFactory? verifierFactory,
    Duration? resumeBackoffStep,
    bool? saveTargetNeedsUserActivation,
  })  : _decryptStream = decryptStream ?? decryptTransactionDataStream,
        _resumeBackoffStep = resumeBackoffStep ?? _defaultResumeBackoffStep,
        _saveTargetNeedsUserActivation =
            saveTargetNeedsUserActivation ?? kIsWeb {
    _source = source ?? GatewayDownloadSource(_arweave);
    _verifierFactory = verifierFactory ?? _dataItemVerifierFor;
  }

  final Completer<String> _cancelWithReason = Completer<String>();

  final StreamController<LinearProgress> downloadProgressController =
      StreamController<LinearProgress>.broadcast();

  Stream<LinearProgress> get downloadProgress =>
      downloadProgressController.stream;

  final StreamController<DownloadResumeEvent> _resumeEvents =
      StreamController<DownloadResumeEvent>.broadcast();

  @override
  Stream<DownloadResumeEvent> get resumeEvents => _resumeEvents.stream;

  Completer<DataItemIntegrityResult> _integrity =
      Completer<DataItemIntegrityResult>()
        ..complete(
          const DataItemIntegrityResult.notVerified('No download has run yet'),
        );

  @override
  Future<DataItemIntegrityResult> get integrity => _integrity.future;

  /// How much of the progress bar the buffered AES-GCM download owns. The
  /// remainder belongs to the save, which cannot write a byte until the MAC
  /// has passed, however early it is opened.
  static const _gcmDownloadProgressShare = 95.0;

  /// How many times a stream may be re-requested before the download gives up.
  /// The counter resets whenever an attempt delivers bytes, so a long download
  /// that hiccups repeatedly still finishes.
  static const _maxResumeAttempts = 3;

  /// The ceiling that never resets.
  ///
  /// [_maxResumeAttempts] alone cannot bound the loop: a gateway that dribbles
  /// a single byte and drops the connection *has* made progress, so it earns a
  /// fresh budget every time and the download reconnects forever. Genuine
  /// progress is still not punished — a download that recovers cleanly a dozen
  /// times is pathological by any measure, and restarting is a better answer
  /// than an invisible infinite loop.
  static const _maxTotalResumeAttempts = 12;

  /// Grows with consecutive failures, so a gateway that is refusing to serve
  /// is not hammered. Reset along with [_maxResumeAttempts]'s counter, so a
  /// download that recovers pays the small delay again rather than the large
  /// one.
  static const _defaultResumeBackoffStep = Duration(milliseconds: 250);
  static const _maxResumeBackoff = Duration(seconds: 4);

  /// The integrity lookup runs alongside the first bytes; this bounds how long
  /// it may hold up the *tap*, never the download itself.
  static const _integrityLookupTimeout = Duration(seconds: 10);

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
    // Off by default, and nothing in the app turns it on. See the long note
    // at the `verifierFuture` in [_getFileStream] for why a download must not
    // depend on a GraphQL round trip.
    bool verifyIntegrity = false,
  }) async {
    _resetIntegrity();

    final isPrivateFile =
        fileKey != null && cipher != null && cipherIvString != null;

    // §3.1 — every AES-GCM file that *can* be held in memory, on every
    // platform, is buffered and authenticated before anything reaches the
    // disk. The larger ones fall through to the streaming path below, which
    // reports an honest verdict instead of refusing to download at all.
    if (!isManifest &&
        isPrivateFile &&
        cipher == Cipher.aes256gcm &&
        fileSize <= DownloadPolicy.maxBufferedCiphertextBytes) {
      return _downloadAuthenticatedGcmAndSave(
        txId: txId,
        fileSize: fileSize,
        fileName: fileName,
        lastModifiedDate: lastModifiedDate,
        contentType: contentType,
        cipher: cipher,
        cipherIvString: cipherIvString,
        fileKey: fileKey,
        verifyDownload: verifyDownload,
      );
    }

    Stream<Uint8List> saveStream;

    // What to let go of if the save ends without ever reading a byte. A
    // manifest has nothing open; a file stream does. See [_PreparedStream].
    var releaseIfUnread = _releaseNothing;

    try {
      if (isManifest) {
        saveStream = await _getManifestStream(txId);
        _completeIntegrity(const DataItemIntegrityResult.notVerified(
          'Manifests are fetched as a whole document, not as a signed data '
          'item stream',
        ));
      } else {
        final prepared = await _getFileStream(
          txId: txId,
          fileSize: fileSize,
          fileName: fileName,
          lastModifiedDate: lastModifiedDate,
          contentType: contentType,
          fileKey: fileKey,
          cipher: cipher,
          cipherIvString: cipherIvString,
          verifyDownload: verifyDownload,
          verifyIntegrity: verifyIntegrity,
        );

        saveStream = prepared.stream;
        releaseIfUnread = prepared.release;
      }
    } catch (e) {
      // Nobody is left to reach a verdict; never leave [integrity] hanging.
      _completeIntegrity(
        DataItemIntegrityResult.notVerified('The download did not start: $e'),
      );
      rethrow;
    }

    final IOFile file;

    try {
      file = await _ioFileAdapter.fromReadStreamGenerator(
        ([s, e]) => saveStream,
        fileSize,
        name: fileName,
        lastModifiedDate: lastModifiedDate,
      );
    } catch (e) {
      // The stream was opened and will now never be handed to a saver.
      releaseIfUnread();
      rethrow;
    }

    return _saveToDisk(file, onSettled: releaseIfUnread);
  }

  /// The release for a path that acquired nothing.
  static void _releaseNothing() {}

  @override
  Future<void> abortDownload() {
    if (!_cancelWithReason.isCompleted) {
      _cancelWithReason.complete('Download aborted');
    }
    _completeIntegrity(
      const DataItemIntegrityResult.notVerified('The download was cancelled'),
    );
    logger.d('Download aborted');
    return Future.value();
  }

  /// Writes [file] out, reporting save progress as a percentage.
  ///
  /// This is the save half of [downloadFile], extracted so that the buffered
  /// AES-GCM path and the streaming path share one implementation.
  ///
  /// The downloader owns the `finalize` completer, and it is the only party
  /// that can answer the question the savers ask with it: *should what you
  /// wrote be kept?* It says `true` the moment the last byte has been handed
  /// over, and `false` on a cancel.
  ///
  /// [onSettled] runs once, when the save is over however it ended. It is how
  /// a download that was opened eagerly gets released when the saver never
  /// read it — see [_PreparedStream].
  ///
  /// That ownership is not a detail. `DartIOFileSaver.saveStream`
  /// (`packages/ardrive_io/lib/src/mobile/mobile_io.dart`) blocks on
  /// `finalize.future` *after* it has written the whole file, so a downloader
  /// that only completed it on cancel left every mobile save hanging at 100%
  /// — and the only way to unblock it, pressing Cancel, deleted the finished
  /// file. The web savers complete it themselves, which is why only mobile
  /// ever showed it.
  Stream<double> _saveToDisk(IOFile file, {void Function()? onSettled}) {
    final finalize = Completer<bool>();

    void settleFinalize(bool keepWhatWasWritten) {
      if (!finalize.isCompleted) finalize.complete(keepWhatWasWritten);
    }

    unawaited(_cancelWithReason.future.then(
      (_) {
        logger.d('Download aborted');
        settleFinalize(false);
      },
      onError: (Object _) => settleFinalize(false),
    ));

    // The savers turn a failure of the *source* stream into `saveResult:
    // false` (`web_io.dart`'s `on Exception`, `mobile_io.dart`'s `catch`),
    // which is indistinguishable from a cancel by the time it gets here.
    // Watching the stream ourselves is what keeps a dead gateway from being
    // reported as "Download cancelled".
    Object? sourceError;
    StackTrace? sourceStackTrace;

    final observed = _ObservedIOFile(
      file,
      onDrained: () => settleFinalize(true),
      onFailed: (e, s) {
        sourceError ??= e;
        sourceStackTrace ??= s;
      },
    );

    bool? saveResult;
    var bytesSaved = 0;

    logger.i('Saving file...');

    final progressController = StreamController<double>();

    final subscription =
        _ardriveIo.saveFileStream(observed, finalize).listen((saveStatus) {
      if (saveStatus.saveResult == null) {
        final progress = saveStatus.bytesSaved / saveStatus.totalBytes;
        bytesSaved += saveStatus.bytesSaved;

        logger.d('Saving file progress: ${progress * 100}%');

        progressController.sink.add(progress * 100);
      } else {
        saveResult = saveStatus.saveResult!;
      }
    });

    // A stream that ends in an error fires **both** `onError` and `onDone`, and
    // either one can be the handler that settles this controller. Whichever
    // arrives first wins; the second must not touch a closed controller, or the
    // save fails with `Bad state: Cannot add event after closing` instead of
    // with whatever actually went wrong.
    var settled = false;

    void settle([Object? error, StackTrace? stackTrace]) {
      if (settled) {
        return;
      }
      settled = true;
      onSettled?.call();

      if (error != null) {
        progressController.addError(error, stackTrace);
      }

      progressController.close();
      subscription.cancel();
    }

    subscription.onDone(() {
      final failure = sourceError;

      if (failure != null) {
        settle(failure, sourceStackTrace);
      } else if (_cancelWithReason.isCompleted || saveResult == false) {
        settle(const DownloadCancelledException());
      } else {
        logger.d('File saved with success');
        settle();
      }
    });

    subscription.onError((e, s) {
      if (settled) {
        return;
      }

      logger.e(
        'Failed to download of save the file. Closing progressController...',
        e,
        s,
      );

      final failure = sourceError;
      if (failure != null) {
        // The download is what broke; the save never had a chance.
        settle(failure, sourceStackTrace);
        return;
      }

      // This branch reports more than one error, and `settle` closes after the
      // first, so it claims the controller up front and closes at the end.
      settled = true;
      onSettled?.call();

      if (saveResult != true) {
        // verify if the download was aborted before starting the save
        if (bytesSaved == 0) {
          progressController.addError(const DownloadCancelledException());
        }

        progressController.addError(Exception('Failed to save file'));
      }
      // TODO: we can show a different message for different errors e.g. when `e` is ActionCanceledException
      progressController.addError(e);
      progressController.close();
      subscription.cancel();
      return;
    });

    return progressController.stream;
  }

  Future<Stream<Uint8List>> _getManifestStream(String dataTxId) async {
    logger.i('The file is a manifest. Downloading with gateway fallback...');

    final response = await _arweave.gatewayFallback
        .fetchManifestWithFallback(dataTxId, _arweave.client);

    return Stream.fromIterable([Uint8List.fromList(response.bodyBytes)]);
  }

  // ---------------------------------------------------------------------
  // §3.1 AES-GCM: buffer, authenticate, then save.
  // ---------------------------------------------------------------------

  /// Downloads an AES-GCM file into memory, verifies its MAC, and only then
  /// hands the plaintext to the saver.
  ///
  /// The download never yields a byte until the tag has passed, so nothing
  /// unauthenticated can be written whichever order the two halves run in. The
  /// order itself is [_saveTargetNeedsUserActivation]'s: on the web the saver
  /// is called first, so that the file picker opens while the click that asked
  /// for the download is still fresh, and the download happens inside the
  /// stream the saver reads. Everywhere else the MAC is checked first and the
  /// saver is not called at all if it fails.
  ///
  /// Progress runs 0 → [_gcmDownloadProgressShare] while the ciphertext
  /// arrives, pauses over the (fast) authentication step, and finishes on the
  /// save. The saver's own first status arrives before the download on the
  /// web, so it is not counted until there is something to save.
  Stream<double> _downloadAuthenticatedGcmAndSave({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required String cipher,
    required String cipherIvString,
    required SecretKey fileKey,
    required bool verifyDownload,
  }) {
    final controller = StreamController<double>();

    var authenticated = false;

    void emit(double progress) {
      if (!controller.isClosed) controller.add(progress);
    }

    // Everything that has to happen before a byte may be written.
    Future<Uint8List> download() async {
      try {
        final plaintext = await _downloadAndAuthenticateGcm(
          txId: txId,
          fileSize: fileSize,
          cipher: cipher,
          cipherIvString: cipherIvString,
          fileKey: fileKey,
          verifyDownload: verifyDownload,
          onProgress: (received, expected) => emit(
            (received / expected * _gcmDownloadProgressShare)
                .clamp(0.0, _gcmDownloadProgressShare)
                .toDouble(),
          ),
        );

        // The MAC is the integrity check for this cipher (§3.4.1), and it has
        // just passed over every byte.
        _completeIntegrity(
          DataItemIntegrityResult.verified(bytesHashed: plaintext.length),
        );

        authenticated = true;
        emit(_gcmDownloadProgressShare);

        return plaintext;
      } catch (e) {
        _completeIntegrity(
          e is DownloadIntegrityException
              ? DataItemIntegrityResult.failed(e.reason)
              : DataItemIntegrityResult.notVerified(
                  'The download did not complete: $e'),
        );
        rethrow;
      }
    }

    // Whichever of the two below gets there first, the file is downloaded and
    // authenticated exactly once.
    Future<Uint8List>? started;
    Future<Uint8List> authenticate() => started ??= download();

    Future<void> run() async {
      if (!_saveTargetNeedsUserActivation) await authenticate();

      final file = await _ioFileAdapter.fromReadStreamGenerator(
        // Read by the saver, which on the web has just finished asking the
        // user where to put the file. Authentication happens here, so the
        // stream errors instead of yielding when the tag does not check out —
        // and the saver, seeing a source that failed, keeps nothing.
        ([s, e]) async* {
          yield await authenticate();
        },
        fileSize,
        name: fileName,
        lastModifiedDate: lastModifiedDate,
        contentType: contentType,
      );

      // The save owns the last (100 - [_gcmDownloadProgressShare])%.
      _saveToDisk(file).listen(
        (saveProgress) {
          if (!authenticated) return;
          emit(_gcmDownloadProgressShare +
              saveProgress * (100 - _gcmDownloadProgressShare) / 100);
        },
        onError: (Object e, StackTrace s) {
          if (!controller.isClosed) controller.addError(e, s);
        },
        onDone: () {
          // A saver can end without ever reading the stream — a dismissed file
          // picker is the common one — and then nothing above has reached a
          // verdict. [integrity] still has to answer. Already-settled verdicts
          // win, so this only ever fills a gap.
          _completeIntegrity(const DataItemIntegrityResult.notVerified(
            'The file was never saved, so nothing checked its authentication '
            'tag',
          ));
          if (!controller.isClosed) controller.close();
        },
        cancelOnError: false,
      );
    }

    unawaited(
      // Only reached when the save never started: once it has, it owns the
      // controller and closes it. [authenticate] has already recorded a
      // verdict for anything that went wrong inside it; this is the backstop
      // for everything else, so that [integrity] can never hang.
      run().catchError((Object e, StackTrace s) {
        _completeIntegrity(
          DataItemIntegrityResult.notVerified(
              'The download did not complete: $e'),
        );
        if (!controller.isClosed) {
          controller.addError(e, s);
          controller.close();
        }
      }),
    );

    return controller.stream;
  }

  /// Fetches the whole ciphertext and returns the plaintext only if the AES-GCM
  /// tag verifies.
  ///
  /// Only reached for a file that claims to be at or under
  /// [DownloadPolicy.maxBufferedCiphertextBytes] — its callers route the
  /// larger ones to the streaming path — and bounded again here, in case a
  /// gateway streams more than the file claims. The size check below is
  /// therefore an assertion, not a policy: a caller that skipped the split
  /// gets an error instead of an unbounded buffer.
  Future<Uint8List> _downloadAndAuthenticateGcm({
    required String txId,
    required int fileSize,
    required String cipher,
    required String cipherIvString,
    required SecretKey fileKey,
    required bool verifyDownload,
    void Function(int received, int expected)? onProgress,
  }) async {
    final maxCiphertext =
        DownloadPolicy.maxBufferedCiphertextBytes + gcmMacLengthBytes;

    if (fileSize > DownloadPolicy.maxBufferedCiphertextBytes) {
      throw DownloadTooLargeToAuthenticateException(
        txId,
        fileSize,
        DownloadPolicy.maxBufferedCiphertextBytes,
      );
    }

    final response = await _source.open(
      txId: txId,
      verifyDownload: verifyDownload,
    );

    final expected = fileSize + gcmMacLengthBytes;
    final buffer = BytesBuilder(copy: false);

    try {
      await for (final chunk in _withStallDetection(response.stream, txId)) {
        if (_cancelWithReason.isCompleted) {
          throw const DownloadCancelledException();
        }

        buffer.add(chunk);

        if (buffer.length > maxCiphertext) {
          throw DownloadTooLargeToAuthenticateException(
            txId,
            buffer.length,
            DownloadPolicy.maxBufferedCiphertextBytes,
          );
        }

        onProgress?.call(buffer.length, expected);
      }
    } catch (_) {
      response.cancel();
      rethrow;
    }

    final ciphertext = buffer.takeBytes();

    try {
      return await decryptTransactionData(
        cipher,
        cipherIvString,
        ciphertext,
        fileKey,
      );
    } on TransactionDecryptionException catch (e, s) {
      throw _authenticationFailed(txId, e, s);
    } on SecretBoxAuthenticationError catch (e, s) {
      // `decryptTransactionData` means to translate this one itself, but its
      // try/catch does not span the async gap, so it surfaces raw. Either way
      // it means the same thing: the tag did not match.
      throw _authenticationFailed(txId, e, s);
    }
  }

  DownloadIntegrityException _authenticationFailed(
    String txId,
    Object error,
    StackTrace stackTrace,
  ) {
    logger.e(
      'AES-GCM authentication failed for $txId. Nothing was written.',
      error,
      stackTrace,
    );

    return DownloadIntegrityException(
      txId,
      'The file did not pass its AES-GCM authentication check',
    );
  }

  // ---------------------------------------------------------------------
  // §3.2/§3.3 AES-CTR and public: stream, seek, resume.
  // ---------------------------------------------------------------------

  Future<_PreparedStream> _getFileStream({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload = false,
    bool verifyIntegrity = false,
  }) async {
    logger.d('The file is not a manifest. Downloading it from Arweave...');
    logger.d('verifying download: $verifyDownload');

    final isPrivateFile =
        fileKey != null && cipher != null && cipherIvString != null;

    // The narrow, deliberate exception to §3.1. See [_oversizedGcmCaveat].
    var gcmTooLargeToBuffer = false;

    if (isPrivateFile) {
      if (cipher == Cipher.aes256gcm) {
        if (fileSize <= DownloadPolicy.maxBufferedCiphertextBytes) {
          // The tripwire for F24: streaming AES-GCM trims the tag and never
          // checks it. Every GCM file that fits in memory — which is every one
          // this uploader has written since the GCM/CTR split — must go
          // through the buffered path.
          throw StateError(
            'AES-GCM must be buffered and MAC-verified, never streamed',
          );
        }

        // Above the cap there is no honest alternative. AES-GCM was ArDrive's
        // only symmetric cipher for years (docs/ArweaveFS.md) and ardrive-cli
        // still writes it at any size, so refusing here would mean a large
        // legacy private file could not be downloaded at all. It streams,
        // unauthenticated, and says so — see [_oversizedGcmCaveat].
        gcmTooLargeToBuffer = true;
        logger.w(
          'AES-GCM file $txId is $fileSize bytes, over the '
          '${DownloadPolicy.maxBufferedCiphertextBytes} byte buffer limit: '
          'streaming it without checking its authentication tag.',
        );
      } else if (cipher != Cipher.aes256ctr) {
        logger.e('Unknown cipher: $cipher. Throwing exception.');
        throw Exception('Unknown cipher: $cipher');
      }

      logger.d('Decrypting file with cipher: $cipher');
    }

    Uint8List? cipherIv;
    Uint8List? keyData;

    if (isPrivateFile) {
      cipherIv = decodeBase64ToBytes(cipherIvString);
      keyData = Uint8List.fromList(await fileKey.extractBytes());
    }

    // Off by default: a download must not depend on a GraphQL round trip.
    //
    // This check was added in #2175 and turned out to cost more than it
    // bought. Three things, each independently disqualifying:
    //
    // * It is not free, and not concurrent either. Starting the future here
    //   was meant to overlap it with the transfer, but the stream awaits it
    //   before yielding a single byte (`verifier ??= await verifierFuture`),
    //   so a slow lookup delays the first byte by up to
    //   [_integrityLookupTimeout].
    // * It reports failures that are not failures. Gateways return `anchor`
    //   and `recipient` as empty strings - checked live against goldsky,
    //   permagate.io, turbo-gateway.com and vilenarios.com - so any data item
    //   that actually carries one deep-hashes differently here than it did
    //   when it was signed, and a healthy file is reported as `failed`. That
    //   verdict is not a footnote: it replaces the success dialog with
    //   "the file may be corrupted".
    // * A recipient on a connection that `arweave.net` rate limits gets the
    //   10s timeout on every download, because that host is what
    //   [GraphQLRetry] falls back to.
    //
    // What is kept is the check that costs nothing: AES-GCM files are still
    // buffered and MAC-verified (§3.4.1), which is a real integrity guarantee
    // computed locally over the bytes in hand. Only the signature check, the
    // one that needs the network to say anything at all, is gone.
    //
    // Callers can still ask for it explicitly. Nothing does today.
    final verifierFuture = verifyIntegrity
        ? _verifierFactory(txId)
        : Future.value(StreamedDataItemVerifier.unavailable(
            'Integrity checking was not requested for this download'));

    // Opened *before* the stream is handed to a saver, so that a gateway that
    // 404s, rate-limits, or cannot be reached throws out of `downloadFile`
    // itself. Inside the generator it would surface later, from within the
    // saver, which swallows it into `saveResult: false` — and the user would
    // be told they cancelled a download they never started, after being asked
    // where to put it.
    final firstResponse = await _source.open(
      txId: txId,
      verifyDownload: verifyDownload,
    );

    // ...which is why the caller is handed a release as well as a stream: what
    // is opened eagerly cannot be released only by a generator that may never
    // run. See [_PreparedStream].
    var consumed = false;
    var released = false;

    Stream<Uint8List> plaintext() async* {
      consumed = true;

      yield* _resilientPlaintextStream(
        txId: txId,
        fileSize: fileSize,
        verifyDownload: verifyDownload,
        cipher: isPrivateFile ? cipher : null,
        cipherIv: cipherIv,
        keyData: keyData,
        verifierFuture: verifierFuture,
        firstResponse: firstResponse,
        gcmTooLargeToBuffer: gcmTooLargeToBuffer,
        integrityCaveat: gcmTooLargeToBuffer ? _oversizedGcmCaveat : null,
      );
    }

    void release() {
      // Once the generator has started it owns both of these, and its `finally`
      // is what settles them.
      if (consumed || released) return;
      released = true;

      logger.d(
        'The download of $txId was never read; releasing the connection and '
        'the integrity check that were opened for it.',
      );

      firstResponse.cancel();

      // The verifier is a hash pipeline waiting on chunks that will now never
      // arrive. [StreamedDataItemVerifier.markUnverifiable] cancels its feed,
      // which unwinds the pending verification instead of leaving it parked
      // for the lifetime of the app.
      unawaited(
        verifierFuture.then(
          (verifier) => verifier.markUnverifiable(_neverReadCaveat),
          // The factory answers with an `unavailable` verifier rather than an
          // error, but an injected one need not, and nothing else is left to
          // observe this future.
          onError: (Object e) => logger.d(
            'The integrity check for $txId could not even be prepared: $e',
          ),
        ),
      );

      // [_resilientPlaintextStream]'s `finally` is the usual answer to
      // [integrity]; it never runs on this path, and an unanswered verdict is
      // a future the caller can wait on for ever.
      _completeIntegrity(
        const DataItemIntegrityResult.notVerified(_neverReadCaveat),
      );
    }

    return _PreparedStream(plaintext(), release);
  }

  /// The verdict for a download that was opened and then abandoned.
  static const _neverReadCaveat =
      'The download was never read, so nothing checked its integrity';

  /// Why an oversized AES-GCM download cannot claim its cipher checked out.
  static const _oversizedGcmCaveat =
      'The file is larger than the buffered limit for AES-GCM, so its '
      'authentication tag could not be checked';

  /// The file's plaintext, from byte 0 to the end, re-requesting from the last
  /// delivered byte whenever the transport dies mid-stream.
  ///
  /// Resume is expressed at the *plaintext* offset, which for AES-CTR and for
  /// public files is also the ciphertext offset. The offset is aligned down to
  /// the AES block, the decryptor is rebuilt with that start offset, and the
  /// ≤15 bytes of overlap are dropped — so the bytes handed downstream are
  /// byte-identical to an uninterrupted download.
  ///
  /// A gateway that answers a `Range` request with `200 OK` is sending the body
  /// from byte 0. That is detected by comparing
  /// [DownloadSourceResponse.startOffsetBytes] against what was asked for, and
  /// it aborts the download rather than splicing: consuming a full body to
  /// salvage a tail defeats the purpose, and writing it at the resume offset
  /// would silently corrupt the file. The caller's retry then restarts cleanly.
  Stream<Uint8List> _resilientPlaintextStream({
    required String txId,
    required int fileSize,
    required bool verifyDownload,
    required String? cipher,
    required Uint8List? cipherIv,
    required Uint8List? keyData,
    required Future<StreamedDataItemVerifier> verifierFuture,
    DownloadSourceResponse? firstResponse,
    bool gcmTooLargeToBuffer = false,
    String? integrityCaveat,
  }) async* {
    final encrypted = cipher != null;

    StreamedDataItemVerifier? verifier;
    var delivered = 0;
    var attempts = 0;
    var totalAttempts = 0;
    var pending = firstResponse;

    try {
      while (true) {
        final resumeFrom = resumeOffsetFor(delivered, encrypted: encrypted);
        var toSkip = delivered - resumeFrom;

        if (resumeFrom > 0 && verifyDownload) {
          // The chunk-level check the arweave client runs for L1 transactions
          // needs the whole transaction; a ranged request cannot honour it, so
          // restarting is the only correct answer.
          throw DownloadResumeNotSupportedException(
            txId,
            resumeFrom,
            null,
            'the download is chunk-verified, which needs the whole transaction',
          );
        }

        late final DownloadSourceResponse response;
        final prefetched = pending;
        pending = null;

        if (prefetched != null) {
          // The caller already opened byte 0 so that a gateway failure would
          // surface before anything else happened.
          response = prefetched;
        } else {
          try {
            response = await _source.open(
              txId: txId,
              startOffsetBytes: resumeFrom,
              verifyDownload: verifyDownload,
            );
          } catch (e) {
            if (resumeFrom == 0 ||
                attempts >= _maxResumeAttempts ||
                totalAttempts >= _maxTotalResumeAttempts) {
              rethrow;
            }
            attempts++;
            totalAttempts++;
            _announceResume(txId, resumeFrom, attempts, e);
            await _backOffBeforeResume(attempts);
            continue;
          }
        }

        // Branch on what came back, never on having sent the header.
        if (response.startOffsetBytes != resumeFrom) {
          response.cancel();
          throw DownloadResumeNotSupportedException(
            txId,
            resumeFrom,
            response.statusCode,
            'the gateway returned the body from byte '
            '${response.startOffsetBytes} instead of $resumeFrom',
          );
        }

        final activeVerifier = verifier ??= await verifierFuture;

        if (resumeFrom > 0) {
          activeVerifier.markUnverifiable(
            'Resumed at byte $resumeFrom: the hash of everything before that '
            'belongs to a stream that is gone',
          );
        }

        final ciphertext = activeVerifier.tap(
          _withStallDetection(response.stream, txId)
              .transform(listIntToUint8ListTransformer),
        );

        var plaintext = ciphertext;
        if (cipher != null) {
          plaintext = await _decryptStream(
            cipher,
            cipherIv!,
            ciphertext,
            keyData!,
            fileSize,
            startOffsetBytes: resumeFrom,
            gcmTooLargeToBuffer: gcmTooLargeToBuffer,
          );
        }

        final deliveredBefore = delivered;

        try {
          await for (var chunk in plaintext) {
            if (toSkip > 0) {
              if (chunk.length <= toSkip) {
                toSkip -= chunk.length;
                continue;
              }
              chunk = Uint8List.sublistView(chunk, toSkip);
              toSkip = 0;
            }

            delivered += chunk.length;
            yield chunk;
          }

          return;
        } catch (e) {
          response.cancel();

          // An attempt that made progress earns a fresh budget — but only
          // against [_maxResumeAttempts]. [_maxTotalResumeAttempts] is what
          // ends a gateway that dribbles a byte at a time.
          if (delivered > deliveredBefore) attempts = 0;
          if (delivered == 0 ||
              attempts >= _maxResumeAttempts ||
              totalAttempts >= _maxTotalResumeAttempts) {
            rethrow;
          }

          attempts++;
          totalAttempts++;
          _announceResume(
            txId,
            resumeOffsetFor(delivered, encrypted: encrypted),
            attempts,
            e,
          );
          await _backOffBeforeResume(attempts);
        }
      }
    } finally {
      final settled = verifier;
      if (settled == null) {
        _completeIntegrity(DataItemIntegrityResult.notVerified(
          integrityCaveat == null
              ? 'The download never delivered any bytes'
              : 'The download never delivered any bytes. $integrityCaveat',
        ));
      } else {
        // Deliberately not awaited: the verdict must never hold up the save.
        unawaited(settled.finish().then((result) {
          _completeIntegrity(_withIntegrityCaveat(result, integrityCaveat));
        }));
      }
    }
  }

  Future<void> _backOffBeforeResume(int attempt) {
    final delay = _resumeBackoffStep * attempt;
    return Future<void>.delayed(
      delay > _maxResumeBackoff ? _maxResumeBackoff : delay,
    );
  }

  /// Adds [caveat] to a verdict that did not reach one of its own.
  ///
  /// A `verified` or `failed` verdict is left alone: those come from the data
  /// item signature over the very bytes that arrived (§3.4.2), which is a real
  /// answer about this file and is not weakened — or improved — by the cipher
  /// having no checkable tag. It is the *absence* of a verdict that needs to
  /// name why nothing else was available.
  static DataItemIntegrityResult _withIntegrityCaveat(
    DataItemIntegrityResult result,
    String? caveat,
  ) {
    if (caveat == null || !result.isNotVerified) return result;

    final reason = result.reason;

    return DataItemIntegrityResult.notVerified(
      reason == null || reason.isEmpty ? caveat : '$reason. $caveat',
      bytesHashed: result.bytesHashed,
    );
  }

  void _announceResume(String txId, int offset, int attempt, Object cause) {
    logger.w(
      'Download of $txId was interrupted at byte $offset '
      '(attempt $attempt): $cause',
    );

    if (!_resumeEvents.isClosed) {
      _resumeEvents.add(DownloadResumeEvent(
        txId: txId,
        resumedFromBytes: offset,
        attempt: attempt,
        cause: cause,
      ));
    }
  }

  /// The chain-based integrity check for one transaction (§3.4.2).
  Future<StreamedDataItemVerifier> _dataItemVerifierFor(String txId) async {
    try {
      final tx = await _arweave
          .getTransactionDetailsWithSignature(txId)
          .timeout(_integrityLookupTimeout);

      if (tx == null) {
        return StreamedDataItemVerifier.unavailable(
          'No transaction details were returned for $txId',
        );
      }

      if (tx.bundledIn == null) {
        return StreamedDataItemVerifier.unavailable(
          '$txId is an L1 transaction: its integrity comes from its data_root '
          'and the chunk level check, not from a data item signature',
        );
      }

      return StreamedDataItemVerifier(
        dataItemId: txId,
        owner: tx.ownerKey.key,
        signature: tx.signature,
        anchor: tx.anchor,
        target: tx.recipient,
        tags: [for (final tag in tx.tags) DataItemTag(tag.name, tag.value)],
      );
    } catch (e) {
      logger.w('Could not prepare the integrity check for $txId: $e');
      return StreamedDataItemVerifier.unavailable(
        'Could not fetch the data item details: $e',
      );
    }
  }

  void _resetIntegrity() {
    _integrity = Completer<DataItemIntegrityResult>();
  }

  void _completeIntegrity(DataItemIntegrityResult result) {
    if (!_integrity.isCompleted) _integrity.complete(result);
  }

  static const _stallTimeout = Duration(seconds: 60);

  /// Wraps a download stream with stall detection. After the first chunk
  /// arrives, if no subsequent chunk arrives within [_stallTimeout], emits
  /// a [DownloadStalledException]. If the stream completes before any chunks
  /// (empty file), no stall error is raised.
  Stream<List<int>> _withStallDetection(
      Stream<List<int>> source, String txId) {
    final controller = StreamController<List<int>>();
    Timer? stallTimer;
    late final StreamSubscription<List<int>> subscription;

    void resetTimer() {
      stallTimer?.cancel();
      stallTimer = Timer(_stallTimeout, () {
        subscription.cancel();
        if (!controller.isClosed) {
          controller.addError(DownloadStalledException(txId, _stallTimeout));
          controller.close();
        }
      });
    }

    subscription = source.listen(
      (chunk) {
        if (controller.isClosed) return;
        resetTimer();
        controller.add(chunk);
      },
      onError: (Object e, StackTrace s) {
        stallTimer?.cancel();
        if (!controller.isClosed) {
          controller.addError(e, s);
        }
      },
      onDone: () {
        stallTimer?.cancel();
        if (!controller.isClosed) {
          controller.close();
        }
      },
    );

    controller.onCancel = () {
      stallTimer?.cancel();
      subscription.cancel();
    };

    return controller.stream;
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
  }) async {
    _resetIntegrity();

    final isPrivateFile =
        fileKey != null && cipher != null && cipherIvString != null;

    // Same split as [downloadFile]: buffer and authenticate what fits, stream
    // what does not, so that a large legacy AES-GCM file is not singled out
    // for refusal when the same size in AES-CTR streams without complaint.
    if (isPrivateFile &&
        cipher == Cipher.aes256gcm &&
        fileSize <= DownloadPolicy.maxBufferedCiphertextBytes) {
      try {
        final plaintext = await _downloadAndAuthenticateGcm(
          txId: txId,
          fileSize: fileSize,
          cipher: cipher,
          cipherIvString: cipherIvString,
          fileKey: fileKey,
          verifyDownload: verifyDownload,
        );

        _completeIntegrity(
          DataItemIntegrityResult.verified(bytesHashed: plaintext.length),
        );

        return plaintext;
      } on DownloadIntegrityException catch (e) {
        _completeIntegrity(DataItemIntegrityResult.failed(e.reason));
        rethrow;
      }
    }

    // Nothing between here and the `toList` below can throw or await, so this
    // path always listens to what it opened and never needs
    // [_PreparedStream.release].
    final _PreparedStream prepared;
    try {
      prepared = await _getFileStream(
        txId: txId,
        fileSize: fileSize,
        fileName: fileName,
        lastModifiedDate: lastModifiedDate,
        contentType: contentType,
        fileKey: fileKey,
        cipher: cipher,
        cipherIvString: cipherIvString,
        verifyDownload: verifyDownload,
        // In-memory reads are thumbnails and previews: they happen constantly
        // and are not what the user asked to keep, so they do not buy a
        // GraphQL round trip each.
        verifyIntegrity: false,
      );
    } catch (e) {
      _completeIntegrity(
        DataItemIntegrityResult.notVerified('The download did not start: $e'),
      );
      rethrow;
    }

    final data = await prepared.stream.toList();

    return Uint8List.fromList(data.expand((element) => element).toList());
  }
}

/// A plaintext stream, plus the release of everything acquired to open it.
///
/// [_ArDriveDownloader._getFileStream] opens the first gateway response and
/// starts the integrity verifier *before* it returns. That is deliberate: a
/// gateway that 404s, rate-limits or cannot be reached has to throw out of
/// `downloadFile` itself, because inside the generator it would surface from
/// within the saver, which swallows it into `saveResult: false` — and the user
/// would be told they cancelled a download they never started, after being
/// asked where to put it.
///
/// The cost of opening early is that both resources are released only by the
/// generator's `finally`, which does not run until something listens. A saver
/// that ends without a single read — a dismissed `showSaveFilePicker` is the
/// common case — would otherwise leave the connection open, the verifier's
/// hash pipeline parked for the lifetime of the app, and the integrity verdict
/// unanswered for a caller that awaits it.
class _PreparedStream {
  const _PreparedStream(this.stream, this.release);

  final Stream<Uint8List> stream;

  /// Releases the connection and the verifier, unless [stream] has been
  /// listened to — in which case the generator owns them. Idempotent.
  final void Function() release;
}

/// An [IOFile] that tells the downloader how the saver's read of it ended.
///
/// The savers are the ones that pull the bytes, so without this the downloader
/// cannot tell "the whole file was handed over" from "the gateway died
/// halfway" — both arrive as the same `saveResult: false`. Delegates
/// everything else untouched.
class _ObservedIOFile implements IOFile {
  _ObservedIOFile(
    this._inner, {
    required this.onDrained,
    required this.onFailed,
  });

  final IOFile _inner;

  /// Called once the saver has read the file to its end, without error.
  final void Function() onDrained;

  /// Called with the error that ended the read early.
  final void Function(Object error, StackTrace stackTrace) onFailed;

  @override
  String get name => _inner.name;

  @override
  String get path => _inner.path;

  @override
  DateTime get lastModifiedDate => _inner.lastModifiedDate;

  @override
  String get contentType => _inner.contentType;

  @override
  FutureOr<int> get length => _inner.length;

  @override
  Future<Uint8List> readAsBytes() => _inner.readAsBytes();

  @override
  Future<String> readAsString() => _inner.readAsString();

  @override
  Stream<Uint8List> openReadStream([int start = 0, int? end]) async* {
    // A ranged read says nothing about whether the whole file was delivered.
    final isWholeFile = start == 0 && end == null;

    try {
      await for (final chunk in _inner.openReadStream(start, end)) {
        yield chunk;
      }
    } catch (e, s) {
      onFailed(e, s);
      rethrow;
    }

    if (isWholeFile) onDrained();
  }
}

/// Where the downloader gets a transaction's bytes from.
///
/// Split out from the downloader so that resume can be exercised without a
/// network: the resume logic only ever sees "here is a stream, and here is the
/// offset it really starts at".
abstract class DownloadSource {
  Future<DownloadSourceResponse> open({
    required String txId,
    int startOffsetBytes = 0,
    bool verifyDownload = false,
  });
}

class DownloadSourceResponse {
  DownloadSourceResponse({
    required this.stream,
    required this.startOffsetBytes,
    this.statusCode,
    void Function()? cancel,
  }) : cancel = cancel ?? _noop;

  /// The bytes as they came off the wire — ciphertext, for a private file.
  final Stream<List<int>> stream;

  /// The offset [stream] actually starts at.
  ///
  /// **Never assume this is the offset that was asked for.** Measured
  /// 2026-08-05: `turbo-gateway.com` answers `206 Partial Content` with an
  /// exact `content-range`, while `arweave.net` ignores the `Range` header and
  /// answers `200 OK` with the whole body. A `200` is reported here as `0`.
  final int startOffsetBytes;

  /// The HTTP status, when there was one. `null` for sources that do not speak
  /// HTTP directly.
  final int? statusCode;

  /// Releases the underlying connection.
  final void Function() cancel;

  static void _noop() {}
}

/// The production [DownloadSource].
///
/// A download from byte 0 goes through the existing hedged gateway fallback,
/// unchanged. A resume is a direct `GET {gateway}/{txId}` with a `Range`
/// header, because the arweave client's `download()` does not expose one; it
/// walks the same gateway order and takes the first gateway that actually
/// serves a range.
class GatewayDownloadSource implements DownloadSource {
  GatewayDownloadSource(
    this._arweave, {
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final ArweaveService _arweave;
  final http.Client Function() _clientFactory;

  static const _rangeRequestTimeout = Duration(seconds: 15);
  static const _maxGarFallbacks = 2;

  @override
  Future<DownloadSourceResponse> open({
    required String txId,
    int startOffsetBytes = 0,
    bool verifyDownload = false,
  }) async {
    if (startOffsetBytes == 0) {
      final response = await _arweave.gatewayFallback.downloadWithFallback(
        txId: txId,
        primaryClient: _arweave.client,
        onProgress: (progress, speed) => logger.d(progress.toString()),
        verifyDownload: verifyDownload,
      );

      return DownloadSourceResponse(
        stream: response.$1,
        startOffsetBytes: 0,
        cancel: response.$2,
      );
    }

    return _openRange(txId, startOffsetBytes);
  }

  Future<DownloadSourceResponse> _openRange(String txId, int offset) async {
    Object? lastError;
    var sawIgnoredRange = false;

    for (final origin in _gatewayOrigins()) {
      final client = _clientFactory();

      try {
        final request = http.Request('GET', Uri.parse('$origin/$txId'))
          ..headers['Range'] = 'bytes=$offset-';

        final response =
            await client.send(request).timeout(_rangeRequestTimeout);

        if (response.statusCode != 200 && response.statusCode != 206) {
          lastError = 'HTTP ${response.statusCode} from $origin';
          await _discard(response);
          client.close();
          continue;
        }

        final start = startOffsetFromResponse(
          offset,
          response.statusCode,
          response.headers['content-range'],
        );

        if (start != offset) {
          // The range was ignored. Do not read the body: a full body is
          // exactly what resuming exists to avoid.
          logger.w(
            'Gateway $origin answered a Range request with '
            'HTTP ${response.statusCode}; it cannot serve a resume.',
          );
          sawIgnoredRange = true;
          await _discard(response);
          client.close();
          continue;
        }

        return DownloadSourceResponse(
          stream: response.stream,
          startOffsetBytes: start,
          statusCode: response.statusCode,
          cancel: client.close,
        );
      } catch (e) {
        lastError = e;
        client.close();
      }
    }

    if (sawIgnoredRange) {
      // Reported as "the body starts at 0" so the caller takes its one correct
      // action: abandon this attempt instead of splicing.
      return DownloadSourceResponse(
        stream: Stream<List<int>>.fromIterable(const []),
        startOffsetBytes: 0,
        statusCode: 200,
      );
    }

    throw DownloadNetworkException(txId, lastError?.toString());
  }

  /// The offset a ranged response *actually* starts at.
  ///
  /// Branches on the status, never on having sent the header. Anything other
  /// than `206` means the body starts at byte 0, however large the requested
  /// offset was. When a `206` carries a `content-range`, that header wins over
  /// what was asked for, so a gateway that serves a different range than
  /// requested is caught rather than spliced.
  @visibleForTesting
  static int startOffsetFromResponse(
    int requestedOffset,
    int statusCode,
    String? contentRange,
  ) {
    if (statusCode != 206) return 0;
    return _parseContentRangeStart(contentRange) ?? requestedOffset;
  }

  static int? _parseContentRangeStart(String? contentRange) {
    if (contentRange == null) return null;

    final match = RegExp(r'bytes\s+(\d+)\s*-').firstMatch(contentRange);
    if (match == null) return null;

    return int.tryParse(match.group(1)!);
  }

  /// The same gateway order the hedged fallback uses: primary, up to two GAR
  /// gateways, then arweave.net.
  List<String> _gatewayOrigins() {
    final primary = _arweave.client.api.gatewayUrl;
    final origins = <String>[primary.origin];

    final gateways = _arweave.gatewayFallback.cachedGateways;
    if (gateways != null) {
      var added = 0;
      for (final gateway in gateways) {
        if (added >= _maxGarFallbacks) break;
        if (gateway.settings.fqdn == primary.host) continue;
        origins.add('https://${gateway.settings.fqdn}');
        added++;
      }
    }

    if (primary.host != 'arweave.net') origins.add('https://arweave.net');

    return origins;
  }

  static Future<void> _discard(http.StreamedResponse response) async {
    try {
      final subscription = response.stream.listen(null, cancelOnError: true);
      await subscription.cancel();
    } catch (_) {
      // Nothing to release.
    }
  }
}

/// A mid-stream recovery. See [ArDriveDownloader.resumeEvents].
class DownloadResumeEvent {
  const DownloadResumeEvent({
    required this.txId,
    required this.resumedFromBytes,
    required this.attempt,
    required this.cause,
  });

  final String txId;

  /// The byte the download is picking up from.
  final int resumedFromBytes;

  /// 1 for the first recovery after the last successful stretch.
  final int attempt;

  final Object cause;

  @override
  String toString() => 'DownloadResumeEvent($txId, from $resumedFromBytes, '
      'attempt $attempt, caused by $cause)';
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() {
    return 'Download cancelled';
  }
}

/// The bytes did not pass their cryptographic authentication check.
///
/// Distinct from a network failure on purpose: this one means the file that
/// arrived is not the file that was signed, and **no plaintext has been
/// written to disk**. Retrying the same bytes will not help; the sender or the
/// gateway is the problem.
///
/// On the web the save target is opened before the check can possibly have
/// run, because the file picker cannot outlive the click that asked for the
/// download, so an *empty* file may be left where the user chose to save.
/// Everywhere else nothing is created at all.
class DownloadIntegrityException implements Exception {
  const DownloadIntegrityException(this.txId, this.reason);

  final String txId;
  final String reason;

  @override
  String toString() => 'Integrity check failed for $txId: $reason';
}

/// A resume could not be spliced onto what has already been delivered, so the
/// download has to start over.
///
/// The commonest cause is a gateway that ignores `Range` and answers `200 OK`
/// with the whole body; writing that at the resume offset would corrupt the
/// file, so the download is abandoned instead. Retrying from zero is safe and
/// is what the caller should offer.
class DownloadResumeNotSupportedException implements Exception {
  const DownloadResumeNotSupportedException(
    this.txId,
    this.requestedOffset,
    this.statusCode, [
    this.reason,
  ]);

  final String txId;

  /// The offset the resume asked for.
  final int requestedOffset;

  /// The HTTP status that came back, when there was one.
  final int? statusCode;

  final String? reason;

  @override
  String toString() =>
      'Cannot resume $txId from byte $requestedOffset because '
      '${reason ?? 'the gateway did not serve the range'}'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

/// An AES-GCM download that was supposed to fit in memory does not.
///
/// A file whose *declared* size is over
/// [DownloadPolicy.maxBufferedCiphertextBytes] never gets here — it streams,
/// unauthenticated and reported as such. This is the other case: a file that
/// claimed to be small and then kept sending. The claim and the bytes
/// disagree, so the download stops rather than growing a buffer without a
/// bound.
class DownloadTooLargeToAuthenticateException implements Exception {
  const DownloadTooLargeToAuthenticateException(
    this.txId,
    this.sizeBytes,
    this.limitBytes,
  );

  final String txId;
  final int sizeBytes;
  final int limitBytes;

  @override
  String toString() => 'Refusing to buffer $sizeBytes bytes of AES-GCM data '
      'for $txId; the limit is $limitBytes bytes';
}

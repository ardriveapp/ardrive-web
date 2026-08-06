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
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

/// The 16 byte AES-GCM authentication tag that the uploader concatenates onto
/// the ciphertext.
const gcmMacLengthBytes = 16;

/// Decrypts a ciphertext stream that begins at [startOffsetBytes].
///
/// Defaults to [decryptTransactionDataStream]. It is injectable so that resume
/// can be exercised with an offset-sensitive stand-in in environments where
/// the WebCrypto native library is not loadable.
typedef PrivateStreamDecryptor = Future<Stream<Uint8List>> Function(
  String cipher,
  Uint8List cipherIv,
  Stream<Uint8List> ciphertextStream,
  Uint8List keyData,
  int fileSize, {
  int startOffsetBytes,
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
  ///   through [StreamedDataItemVerifier].
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
  }) {
    // F24: no download path may decrypt AES-GCM without checking the MAC any
    // more. Disarm the class so that an accidental reuse throws instead of
    // quietly handing back unauthenticated plaintext.
    AesGcmStream.allowUnauthenticatedGcmDecryption = false;

    return _ArDriveDownloader(
      ioFileAdapter,
      ardriveIo,
      arweave,
      source: source,
      decryptStream: decryptStream,
      verifierFactory: verifierFactory,
    );
  }
}

class _ArDriveDownloader implements ArDriveDownloader {
  final IOFileAdapter _ioFileAdapter;
  final ArDriveIO _ardriveIo;
  final ArweaveService _arweave;
  final PrivateStreamDecryptor _decryptStream;

  late final DownloadSource _source;
  late final IntegrityVerifierFactory _verifierFactory;

  _ArDriveDownloader(
    this._ioFileAdapter,
    this._ardriveIo,
    this._arweave, {
    DownloadSource? source,
    PrivateStreamDecryptor? decryptStream,
    IntegrityVerifierFactory? verifierFactory,
  }) : _decryptStream = decryptStream ?? decryptTransactionDataStream {
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
  /// remainder belongs to the save, which only starts once the MAC has passed.
  static const _gcmDownloadProgressShare = 95.0;

  /// How many times a stream may be re-requested before the download gives up.
  /// The counter resets whenever an attempt delivers bytes, so a long download
  /// that hiccups repeatedly still finishes.
  static const _maxResumeAttempts = 3;

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
  }) async {
    _resetIntegrity();

    final isPrivateFile =
        fileKey != null && cipher != null && cipherIvString != null;

    // §3.1 — every AES-GCM file, on every platform, is buffered and
    // authenticated before anything reaches the disk.
    if (!isManifest && isPrivateFile && cipher == Cipher.aes256gcm) {
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

    try {
      if (isManifest) {
        saveStream = await _getManifestStream(txId);
        _completeIntegrity(const DataItemIntegrityResult.notVerified(
          'Manifests are fetched as a whole document, not as a signed data '
          'item stream',
        ));
      } else {
        saveStream = await _getFileStream(
          txId: txId,
          fileSize: fileSize,
          fileName: fileName,
          lastModifiedDate: lastModifiedDate,
          contentType: contentType,
          fileKey: fileKey,
          cipher: cipher,
          cipherIvString: cipherIvString,
          verifyDownload: verifyDownload,
        );
      }
    } catch (e) {
      // Nobody is left to reach a verdict; never leave [integrity] hanging.
      _completeIntegrity(
        DataItemIntegrityResult.notVerified('The download did not start: $e'),
      );
      rethrow;
    }

    final file = await _ioFileAdapter.fromReadStreamGenerator(
      ([s, e]) => saveStream,
      fileSize,
      name: fileName,
      lastModifiedDate: lastModifiedDate,
    );

    return _saveToDisk(file);
  }

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
  /// This is the save half of [downloadFile], unchanged, extracted so that the
  /// buffered AES-GCM path and the streaming path share one implementation.
  Stream<double> _saveToDisk(IOFile file) {
    final finalize = Completer<bool>();

    Future.any([
      _cancelWithReason.future.then((_) => false),
    ]).then((value) => finalize.complete(value)).catchError((e) {
      logger.d('Download aborted');
      finalize.complete(false);
    });

    bool? saveResult;
    var bytesSaved = 0;

    logger.i('Saving file...');

    final progressController = StreamController<double>();

    final subscription =
        _ardriveIo.saveFileStream(file, finalize).listen((saveStatus) {
      if (saveStatus.saveResult == null) {
        final progress = saveStatus.bytesSaved / saveStatus.totalBytes;
        bytesSaved += saveStatus.bytesSaved;

        logger.d('Saving file progress: ${progress * 100}%');

        progressController.sink.add(progress * 100);
      } else {
        saveResult = saveStatus.saveResult!;
      }
    });

    subscription.onDone(() async {
      if (_cancelWithReason.isCompleted || saveResult == false) {
        progressController.addError(const DownloadCancelledException());
      }

      if (saveResult != false) {
        logger.d('File saved with success');
      }

      progressController.close();
      subscription.cancel();
    });

    subscription.onError((e, s) {
      logger.e(
        'Failed to download of save the file. Closing progressController...',
        e,
        s,
      );
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
  /// Progress runs 0 → [_gcmDownloadProgressShare] while the ciphertext
  /// arrives, pauses over the (fast) authentication step, and finishes on the
  /// save. If authentication fails the stream errors with
  /// [DownloadIntegrityException] and **nothing has been written**: the saver
  /// has not been called at that point.
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

    Future<void> run() async {
      final plaintext = await _downloadAndAuthenticateGcm(
        txId: txId,
        fileSize: fileSize,
        cipher: cipher,
        cipherIvString: cipherIvString,
        fileKey: fileKey,
        verifyDownload: verifyDownload,
        onProgress: (received, expected) {
          if (controller.isClosed) return;
          controller.add(
            (received / expected * _gcmDownloadProgressShare)
                .clamp(0.0, _gcmDownloadProgressShare)
                .toDouble(),
          );
        },
      );

      // The MAC is the integrity check for this cipher (§3.4.1), and it has
      // just passed over every byte.
      _completeIntegrity(
        DataItemIntegrityResult.verified(bytesHashed: plaintext.length),
      );

      final file = await _ioFileAdapter.fromData(
        plaintext,
        name: fileName,
        lastModifiedDate: lastModifiedDate,
        contentType: contentType,
      );

      await controller.addStream(
        _saveToDisk(file).map(
          (saveProgress) =>
              _gcmDownloadProgressShare +
              saveProgress * (100 - _gcmDownloadProgressShare) / 100,
        ),
      );
    }

    unawaited(
      run().catchError((Object e, StackTrace s) {
        _completeIntegrity(
          e is DownloadIntegrityException
              ? DataItemIntegrityResult.failed(e.reason)
              : DataItemIntegrityResult.notVerified(
                  'The download did not complete: $e'),
        );
        if (!controller.isClosed) controller.addError(e, s);
      }).whenComplete(() {
        if (!controller.isClosed) controller.close();
      }),
    );

    return controller.stream;
  }

  /// Fetches the whole ciphertext and returns the plaintext only if the AES-GCM
  /// tag verifies.
  ///
  /// Bounded by construction — the uploader only picks AES-GCM below
  /// [DownloadPolicy.maxBufferedCiphertextBytes] — and bounded again here, in
  /// case a gateway streams more than the file claims.
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

  Future<Stream<Uint8List>> _getFileStream({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload = false,
    bool verifyIntegrity = true,
  }) async {
    logger.d('The file is not a manifest. Downloading it from Arweave...');
    logger.d('verifying download: $verifyDownload');

    final isPrivateFile =
        fileKey != null && cipher != null && cipherIvString != null;

    if (isPrivateFile) {
      if (cipher == Cipher.aes256gcm) {
        // The tripwire for F24: streaming AES-GCM trims the tag and never
        // checks it. Callers must route GCM through the buffered path.
        throw StateError(
          'AES-GCM must be buffered and MAC-verified, never streamed',
        );
      }

      if (cipher != Cipher.aes256ctr) {
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

    // Started here, not inside the stream, so the GraphQL round trip overlaps
    // the download instead of delaying its first byte.
    final verifierFuture = verifyIntegrity
        ? _verifierFactory(txId)
        : Future.value(StreamedDataItemVerifier.unavailable(
            'Integrity checking was not requested for this download'));

    return _resilientPlaintextStream(
      txId: txId,
      fileSize: fileSize,
      verifyDownload: verifyDownload,
      cipher: isPrivateFile ? cipher : null,
      cipherIv: cipherIv,
      keyData: keyData,
      verifierFuture: verifierFuture,
    );
  }

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
  }) async* {
    final encrypted = cipher != null;

    StreamedDataItemVerifier? verifier;
    var delivered = 0;
    var attempts = 0;

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
        try {
          response = await _source.open(
            txId: txId,
            startOffsetBytes: resumeFrom,
            verifyDownload: verifyDownload,
          );
        } catch (e) {
          if (resumeFrom == 0 || attempts >= _maxResumeAttempts) rethrow;
          attempts++;
          _announceResume(txId, resumeFrom, attempts, e);
          continue;
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

          // An attempt that made progress earns a fresh budget.
          if (delivered > deliveredBefore) attempts = 0;
          if (delivered == 0 || attempts >= _maxResumeAttempts) rethrow;

          attempts++;
          _announceResume(
            txId,
            resumeOffsetFor(delivered, encrypted: encrypted),
            attempts,
            e,
          );
        }
      }
    } finally {
      final settled = verifier;
      if (settled == null) {
        _completeIntegrity(const DataItemIntegrityResult.notVerified(
          'The download never delivered any bytes',
        ));
      } else {
        // Deliberately not awaited: the verdict must never hold up the save.
        unawaited(settled.finish().then(_completeIntegrity));
      }
    }
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

    if (isPrivateFile && cipher == Cipher.aes256gcm) {
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

    final Stream<Uint8List> stream;
    try {
      stream = await _getFileStream(
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

    final data = await stream.toList();

    return Uint8List.fromList(data.expand((element) => element).toList());
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
/// arrived is not the file that was signed, and **nothing has been written to
/// disk**. Retrying the same bytes will not help; the sender or the gateway is
/// the problem.
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

/// A file that claims to be AES-GCM is too large to buffer and authenticate.
///
/// The uploader only picks AES-GCM below
/// [DownloadPolicy.maxBufferedCiphertextBytes], so this means the file's
/// metadata and its cipher disagree. Refusing is the safe answer: the
/// alternative is streaming AES-GCM, which cannot check the tag at all.
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

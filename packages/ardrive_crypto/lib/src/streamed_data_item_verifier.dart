import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;

/// The outcome of a streamed integrity check.
///
/// Three outcomes, not two: [notVerified] is honest about the cases where the
/// check could not be run at all (a resumed download whose hash context is
/// gone, a data item signed with something other than an Arweave key, missing
/// GraphQL fields). Reporting those as [failed] would cry wolf on files that
/// are perfectly fine.
enum DataItemIntegrityVerdict {
  /// The bytes that streamed through hash to the data item's signature, and
  /// that signature is valid for the claimed owner.
  verified,

  /// The bytes do not match the signed data item. Treat the data as corrupt
  /// or tampered with.
  failed,

  /// No verdict could be reached. This is *not* evidence of a problem.
  notVerified,
}

/// The result of a streamed integrity check. See [DataItemIntegrityVerdict].
class DataItemIntegrityResult {
  final DataItemIntegrityVerdict verdict;

  /// Why the check failed or could not run. `null` when [isVerified].
  final String? reason;

  /// How many bytes of data the verifier hashed.
  final int bytesHashed;

  const DataItemIntegrityResult._(this.verdict, this.reason, this.bytesHashed);

  const DataItemIntegrityResult.verified({int bytesHashed = 0})
      : this._(DataItemIntegrityVerdict.verified, null, bytesHashed);

  const DataItemIntegrityResult.failed(String reason, {int bytesHashed = 0})
      : this._(DataItemIntegrityVerdict.failed, reason, bytesHashed);

  const DataItemIntegrityResult.notVerified(String reason,
      {int bytesHashed = 0})
      : this._(DataItemIntegrityVerdict.notVerified, reason, bytesHashed);

  bool get isVerified => verdict == DataItemIntegrityVerdict.verified;
  bool get isFailed => verdict == DataItemIntegrityVerdict.failed;
  bool get isNotVerified => verdict == DataItemIntegrityVerdict.notVerified;

  @override
  String toString() => 'DataItemIntegrityResult(${verdict.name}'
      '${reason == null ? '' : ', $reason'}, bytesHashed: $bytesHashed)';
}

/// A transaction tag as GraphQL reports it: plain, *unencoded* name and value.
///
/// The verifier base64url-encodes these itself, so callers never have to think
/// about which representation the deep hash wants.
class DataItemTag {
  final String name;
  final String value;

  const DataItemTag(this.name, this.value);
}

/// Verifies the integrity of an ANS-104 data item's data **while it streams**.
///
/// AES-CTR carries no MAC and the streaming AES-GCM path never checks the one
/// it has, so for everything large — and for public files, which are not
/// encrypted at all — integrity has to come from the chain instead of from the
/// cipher. A data item's signature covers a deep hash whose last segment is
/// the data itself, and that segment can be hashed incrementally as bytes
/// arrive. Nothing needs to be buffered.
///
/// Feed the **bytes as they arrive from the gateway** — the ciphertext for
/// private files, since that is what was signed, not the decrypted plaintext.
///
/// ```dart
/// final verifier = StreamedDataItemVerifier(
///   dataItemId: txId,
///   owner: gql.owner.key,
///   signature: gql.signature,
///   anchor: gql.anchor,
///   target: gql.recipient,
///   tags: gql.tags.map((t) => DataItemTag(t.name, t.value)).toList(),
/// );
///
/// await for (final chunk in verifier.tap(ciphertextStream)) {
///   await sink.add(chunk);
/// }
///
/// final result = await verifier.finish();
/// ```
///
/// Only Arweave-signed (RSA-PSS, 4096 bit) data items can be checked. Anything
/// else — including L1 transactions, which are covered by the chunk/data_root
/// path instead — reports [DataItemIntegrityVerdict.notVerified].
class StreamedDataItemVerifier {
  /// The data item id the bytes are claimed to belong to.
  final String dataItemId;

  final _ChunkFeed _feed = _ChunkFeed();

  /// Completes (never with an error) when the verification pipeline has
  /// settled, so that [addChunk] can never outlive its consumer.
  final Completer<void> _consumerSettled = Completer<void>();

  late final Future<_Outcome> _outcome;

  int _bytesHashed = 0;
  String? _unverifiableReason;
  DataItemIntegrityResult? _result;

  StreamedDataItemVerifier({
    required this.dataItemId,
    required String owner,
    required String signature,
    String target = '',
    String anchor = '',
    List<DataItemTag> tags = const [],
  }) {
    _outcome = _verify(
      owner: owner,
      signature: signature,
      target: target,
      anchor: anchor,
      tags: tags,
    );
  }

  /// A verifier that can never reach a verdict, e.g. because the download was
  /// resumed, the data item is an L1 transaction, or the GraphQL response did
  /// not carry a signature and owner.
  ///
  /// It accepts chunks and ignores them, so callers do not need a nullable
  /// verifier or a second code path.
  StreamedDataItemVerifier.unavailable(String reason) : dataItemId = '' {
    _unverifiableReason = reason;
    _outcome = Future.value(_Outcome.notVerified(reason));
    _consumerSettled.complete();
  }

  /// Bytes handed to the hash so far.
  int get bytesHashed => _bytesHashed;

  /// Whether a verdict is still reachable. `false` once [finish] has run or
  /// [markUnverifiable] has been called.
  bool get isVerifying => _result == null && _unverifiableReason == null;

  /// Hashes [chunk] as part of the data item's data segment.
  ///
  /// The returned future completes once the hash has consumed the chunk, so
  /// awaiting it keeps a fast download from queueing the whole file in memory
  /// ahead of a slower hash.
  Future<void> addChunk(Uint8List chunk) async {
    if (!isVerifying) return;

    _bytesHashed += chunk.length;

    // Whichever comes first: the hash consumed the chunk, or the pipeline died
    // and nothing will ever consume it.
    await Future.any([_feed.add(chunk), _consumerSettled.future]);
  }

  /// Passes [source] through unchanged while feeding every chunk to the hash.
  ///
  /// The caller still has to call [finish] once the stream is done.
  Stream<Uint8List> tap(Stream<Uint8List> source) async* {
    await for (final chunk in source) {
      await addChunk(chunk);
      yield chunk;
    }
  }

  /// Abandons the check: [finish] will report
  /// [DataItemIntegrityVerdict.notVerified] with [reason] no matter what has
  /// been fed so far.
  ///
  /// This is what a resumed download calls. The bytes already on disk were
  /// hashed by a process that is gone, so a hash over the remainder alone
  /// would not match — reporting that as a failure would be a lie.
  ///
  /// It is also **how a verifier is disposed of**. A verifier that is
  /// constructed and then never fed sits with [_verify] parked on
  /// `verifyDataItem`, which is parked on [_ChunkFeed.stream] waiting for
  /// chunks that will never come; the deep hash, the 512 byte owner and the
  /// pending future all stay reachable for as long as something holds the
  /// verifier. Cancelling the feed here is what unwinds that pipeline, so a
  /// caller that gives up on a download — see `_PreparedStream` in
  /// `lib/download/ardrive_downloader.dart` — calls this and is done. There is
  /// deliberately no second `dispose` entry point: two ways to abandon one
  /// check is one more than the number of things that can go wrong here.
  void markUnverifiable(String reason) {
    if (!isVerifying) return;

    _unverifiableReason = reason;
    _feed.cancel();
  }

  /// Ends the stream and returns the verdict. Idempotent.
  Future<DataItemIntegrityResult> finish() async {
    final existing = _result;
    if (existing != null) return existing;

    final unverifiableReason = _unverifiableReason;
    if (unverifiableReason != null) {
      _feed.cancel();
      return _result = DataItemIntegrityResult.notVerified(
        unverifiableReason,
        bytesHashed: _bytesHashed,
      );
    }

    _feed.close();

    final outcome = await _outcome;
    return _result = DataItemIntegrityResult._(
      outcome.verdict,
      outcome.reason,
      _bytesHashed,
    );
  }

  Future<_Outcome> _verify({
    required String owner,
    required String signature,
    required String target,
    required String anchor,
    required List<DataItemTag> tags,
  }) async {
    try {
      if (dataItemId.isEmpty || owner.isEmpty || signature.isEmpty) {
        _feed.cancel();
        return const _Outcome.notVerified(
          'Missing data item id, owner or signature',
        );
      }

      final Uint8List ownerBytes;
      final Uint8List signatureBytes;
      try {
        ownerBytes = utils.decodeBase64ToBytes(owner);
        signatureBytes = utils.decodeBase64ToBytes(signature);
      } on FormatException catch (e) {
        _feed.cancel();
        return _Outcome.notVerified('Malformed owner or signature: $e');
      }

      // Only Arweave RSA-PSS signatures can be checked here. A data item
      // signed with an Ethereum or Solana key is not a corrupt file — we just
      // have no verifier for it, so say so instead of failing it.
      final signatureConfig = SignatureConfig.arweave;
      if (ownerBytes.length != signatureConfig.publicKeyLength ||
          signatureBytes.length != signatureConfig.signatureLength) {
        _feed.cancel();
        return _Outcome.notVerified(
          'Unsupported signature type: expected an Arweave '
          '${signatureConfig.publicKeyLength} byte owner and '
          '${signatureConfig.signatureLength} byte signature, got '
          '${ownerBytes.length} and ${signatureBytes.length}',
        );
      }

      final verified = await verifyDataItem(
        id: dataItemId,
        owner: owner,
        signature: signature,
        target: target,
        anchor: anchor,
        tags: tags.map((tag) => createTag(tag.name, tag.value)).toList(),
        dataStream: _feed.stream(),
      );

      if (verified) return const _Outcome.verified();

      return _Outcome.failed(
        'The data does not match the signature of data item $dataItemId',
      );
    } on _FeedCancelled {
      return const _Outcome.notVerified('Verification was abandoned');
    } catch (e) {
      // Anything unexpected — a broken hash implementation, a malformed tag —
      // means we do not know, not that the file is bad.
      return _Outcome.notVerified('Could not run the integrity check: $e');
    } finally {
      if (!_consumerSettled.isCompleted) _consumerSettled.complete();
    }
  }
}

class _Outcome {
  final DataItemIntegrityVerdict verdict;
  final String? reason;

  const _Outcome(this.verdict, this.reason);

  const _Outcome.verified() : this(DataItemIntegrityVerdict.verified, null);
  const _Outcome.failed(String reason)
      : this(DataItemIntegrityVerdict.failed, reason);
  const _Outcome.notVerified(String reason)
      : this(DataItemIntegrityVerdict.notVerified, reason);
}

class _FeedCancelled implements Exception {
  const _FeedCancelled();
}

class _QueuedChunk {
  final Uint8List chunk;
  final Completer<void> consumed;

  _QueuedChunk(this.chunk, this.consumed);
}

/// Turns pushed chunks into a pull-based stream, one chunk in flight.
///
/// A plain [StreamController] would buffer everything the producer adds before
/// the consumer gets around to it; over a multi-gigabyte download that is the
/// whole file in memory. Here [add] only completes once the consumer has taken
/// the chunk.
class _ChunkFeed {
  final Queue<_QueuedChunk> _queue = Queue<_QueuedChunk>();

  Completer<void>? _dataAvailable;
  bool _closed = false;
  bool _cancelled = false;

  Future<void> add(Uint8List chunk) {
    if (_closed || _cancelled) return Future.value();

    final consumed = Completer<void>();
    _queue.add(_QueuedChunk(chunk, consumed));
    _wake();

    return consumed.future;
  }

  void close() {
    if (_closed || _cancelled) return;

    _closed = true;
    _wake();
  }

  /// Ends the stream with an error, releasing anything waiting on it.
  void cancel() {
    if (_cancelled) return;

    _cancelled = true;
    while (_queue.isNotEmpty) {
      final queued = _queue.removeFirst();
      if (!queued.consumed.isCompleted) queued.consumed.complete();
    }
    _wake();
  }

  Stream<Uint8List> stream() async* {
    while (true) {
      if (_cancelled) throw const _FeedCancelled();

      if (_queue.isEmpty) {
        if (_closed) return;

        final waiter = _dataAvailable = Completer<void>();
        await waiter.future;
        continue;
      }

      final queued = _queue.removeFirst();
      yield queued.chunk;
      if (!queued.consumed.isCompleted) queued.consumed.complete();
    }
  }

  void _wake() {
    final waiter = _dataAvailable;
    _dataAvailable = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }
}

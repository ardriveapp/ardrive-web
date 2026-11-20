import 'dart:async';

import 'package:clock/clock.dart';

/// Looks up the tags of many transactions in one request. Returns an entry for
/// each id the gateway knows; ids it has no node for are simply absent.
typedef TransactionTagsFetch = Future<Map<String, Map<String, String>>>
    Function(List<String> txIds);

/// The gateway answered, and had no transaction with this id. Usually an
/// indexing gap. Not a network failure: asking again right away gets the same
/// answer, so callers must not retry it in a loop.
class TransactionNotFoundException implements Exception {
  const TransactionNotFoundException(this.txId);

  final String txId;

  @override
  String toString() => 'TransactionNotFoundException($txId)';
}

/// Collects the transactions asked for within a short window and reads their
/// tags with one query, instead of one query per transaction.
///
/// - Ids requested within [window], or until [maxBatch] are queued, go out
///   together; more than [maxBatch] split into several queries.
/// - Tags are immutable, so an answer is kept for the life of the batcher.
/// - An id the gateway has no node for completes with
///   [TransactionNotFoundException] and is remembered as missing for
///   [notFoundCooldown], so a tile scrolled back into view straight away does
///   not ask again. Indexing gaps close, so after the cool-down it may try once
///   more.
/// - An error from the query fails every waiter of that query and is not
///   remembered.
class TransactionTagBatcher {
  TransactionTagBatcher({
    required TransactionTagsFetch fetch,
    this.window = const Duration(milliseconds: 40),
    this.maxBatch = 50,
    this.notFoundCooldown = const Duration(seconds: 60),
  })  : assert(maxBatch > 0),
        _fetch = fetch;

  final TransactionTagsFetch _fetch;
  final Duration window;
  final int maxBatch;
  final Duration notFoundCooldown;

  final Map<String, Map<String, String>> _tags = {};
  final Map<String, DateTime> _notFoundAt = {};
  // Asked for and not yet answered, so a second asker joins the first.
  final Map<String, Completer<Map<String, String>>> _waiting = {};
  final List<String> _queue = [];
  Timer? _timer;

  /// The tags of [txId], by name. Throws [TransactionNotFoundException] when
  /// the gateway has no such transaction.
  Future<Map<String, String>> tagsFor(String txId) {
    final known = _tags[txId];
    if (known != null) return Future.value(known);

    final missedAt = _notFoundAt[txId];
    if (missedAt != null) {
      if (clock.now().difference(missedAt) < notFoundCooldown) {
        return Future.error(TransactionNotFoundException(txId));
      }
      _notFoundAt.remove(txId);
    }

    final pending = _waiting[txId];
    if (pending != null) return pending.future;

    final completer = Completer<Map<String, String>>();
    _waiting[txId] = completer;
    _queue.add(txId);

    if (_queue.length >= maxBatch) {
      _flush();
    } else {
      _timer ??= Timer(window, _flush);
    }
    return completer.future;
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;
    while (_queue.isNotEmpty) {
      final take = _queue.length < maxBatch ? _queue.length : maxBatch;
      final ids = _queue.sublist(0, take);
      _queue.removeRange(0, take);
      _send(ids);
    }
  }

  Future<void> _send(List<String> ids) async {
    Map<String, Map<String, String>> found;
    try {
      found = await _fetch(ids);
    } catch (e, s) {
      for (final id in ids) {
        _waiting.remove(id)?.completeError(e, s);
      }
      return;
    }
    final now = clock.now();
    for (final id in ids) {
      final completer = _waiting.remove(id);
      final tags = found[id];
      if (tags != null) {
        _tags[id] = tags;
        completer?.complete(tags);
      } else {
        _notFoundAt[id] = now;
        completer?.completeError(TransactionNotFoundException(id));
      }
    }
  }
}

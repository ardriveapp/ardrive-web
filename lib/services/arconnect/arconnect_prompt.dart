import 'dart:async';

import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:flutter/foundation.dart';

/// Why Wander could not be asked for something.
enum ArConnectUnavailableReason {
  /// The extension is not in this browser.
  notInstalled,

  /// Wander was asked and did not answer in time. A locked Wander shows its
  /// unlock prompt, and when that prompt is closed the request never settles.
  noAnswer,
}

/// Wander was needed and could not be reached, and the person chose not to
/// try again (or nobody could be asked).
class ArConnectUnavailableException implements UntrackedException {
  const ArConnectUnavailableException(this.reason);

  final ArConnectUnavailableReason reason;

  @override
  String toString() => 'ArConnectUnavailableException: ${reason.name}';
}

/// Shown when Wander could not be reached. Resolves true to try again.
///
/// [answered] completes if Wander answers after all while it is shown: the
/// prompt then closes itself and resolves true, so anyone else waiting on it
/// asks again of a Wander that now answers.
typedef ArConnectRetryPrompt = Future<bool> Function(
  ArConnectUnavailableReason reason,
  Future<void> answered,
);

/// Asks Wander for something only a write or a private drive key needs, so
/// that a locked Wander, or a prompt the person closed, can never leave the
/// app waiting.
///
/// Each request has a deadline. When it passes, or the extension is missing,
/// the registered [ArConnectRetryPrompt] says so and offers Try again; Cancel
/// (or no prompt registered) ends in [ArConnectUnavailableException], which
/// the write handles like any other failure.
///
/// Wander's own prompt opens in a window of its own that ArDrive can't see.
/// When the person comes back to ArDrive while a request is still waiting
/// (see [focusRegained]), they most likely closed that window without
/// answering, so the Try again prompt shows then, without waiting out the
/// deadline. Coming back is never taken as an answer: an answer that arrives
/// late, to any request made since, still wins and closes the prompt.
///
/// The state here is static because the thing it describes is: there is one
/// Wander per page, reached through a global JavaScript object, whichever
/// [ArConnectService] instance asks.
class ArConnectPrompt {
  ArConnectPrompt._();

  /// How long a read (permissions, public key) may take. Long enough to type
  /// a password into Wander's unlock prompt; if it runs out while somebody
  /// is still typing, Try again asks once more and the unlocked Wander
  /// answers at once.
  static Duration readTimeout = const Duration(seconds: 20);

  /// How long a signature may take: Wander can show its own confirmation.
  static Duration signTimeout = const Duration(seconds: 60);

  /// Fires when the ArDrive tab gets focus back, or becomes visible again.
  /// Set by the app shell; nothing fires until then.
  static Stream<void> Function() focusRegained = _never;

  /// How long a request may still take to answer once the person is back in
  /// ArDrive. Wander's window closing and its answer arriving race each
  /// other, and an answer on its way should not flash the prompt.
  static Duration focusGrace = const Duration(seconds: 1);

  static Stream<void> _never() => const Stream.empty();

  static ArConnectRetryPrompt? _retryPrompt;
  static _ShownPrompt? _shownPrompt;
  static bool _answered = false;

  /// Whether Wander has answered a request made through [ask] since the page
  /// loaded, which means it was unlocked at the time.
  static bool get hasAnswered => _answered;

  /// Makes [prompt] the one asked when Wander can't be reached. Returns what
  /// removes it again, which does nothing once another prompt has replaced it.
  static VoidCallback registerRetryPrompt(ArConnectRetryPrompt prompt) {
    _retryPrompt = prompt;
    return () {
      if (identical(_retryPrompt, prompt)) _retryPrompt = null;
    };
  }

  /// [request]'s answer from [wander], asked again for as long as the person
  /// chooses Try again. With [askPerson] false nobody is asked: the first
  /// failure throws, for checks that run in the background.
  static Future<T> ask<T>(
    ArConnectService wander,
    Future<T> Function() request, {
    Duration? within,
    bool askPerson = true,
  }) async {
    final requests = _Requests<T>();

    while (true) {
      final ArConnectUnavailableReason reason;
      if (!wander.isExtensionPresent()) {
        reason = ArConnectUnavailableReason.notInstalled;
      } else {
        requests.send(request);
        await _waitForAnswer(
          requests.settled,
          within ?? readTimeout,
          // Coming back early only matters to someone who can be asked.
          watchFocus: askPerson && _retryPrompt != null,
        );
        if (requests.hasSettled) return _answer(requests);
        reason = ArConnectUnavailableReason.noAnswer;
      }

      final prompt = _retryPrompt;
      if (!askPerson || prompt == null) {
        throw ArConnectUnavailableException(reason);
      }

      final retry = await Future.any([
        _show(prompt, reason, requests.settled),
        requests.settled.then((_) => true),
      ]);
      if (requests.hasSettled) return _answer(requests);
      if (!retry) throw ArConnectUnavailableException(reason);
    }
  }

  static Future<T> _answer<T>(_Requests<T> requests) async {
    final answer = await requests.answer;
    _answered = true;
    return answer;
  }

  /// Until [settled], [within] passes, or, with [watchFocus], the person has
  /// been back in ArDrive for [focusGrace].
  static Future<void> _waitForAnswer(
    Future<void> settled,
    Duration within, {
    required bool watchFocus,
  }) {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    Timer? afterFocus;
    final deadline = Timer(within, finish);
    final focus = watchFocus
        ? focusRegained().listen((_) {
            afterFocus ??= Timer(focusGrace, finish);
          })
        : null;
    settled.then((_) => finish());

    return done.future.whenComplete(() {
      deadline.cancel();
      afterFocus?.cancel();
      focus?.cancel();
    });
  }

  /// One prompt at a time: requests that fail together share it, and an
  /// answer to any of them closes it.
  static Future<bool> _show(
    ArConnectRetryPrompt prompt,
    ArConnectUnavailableReason reason,
    Future<void> settled,
  ) {
    final shown = _shownPrompt ?? _open(prompt, reason);
    settled.then((_) => shown.close());
    return shown.choice;
  }

  static _ShownPrompt _open(
    ArConnectRetryPrompt prompt,
    ArConnectUnavailableReason reason,
  ) {
    final shown = _shownPrompt = _ShownPrompt(prompt, reason);
    shown.choice.whenComplete(() {
      if (identical(_shownPrompt, shown)) _shownPrompt = null;
    }).ignore();
    return shown;
  }

  @visibleForTesting
  static void reset() {
    readTimeout = const Duration(seconds: 20);
    signTimeout = const Duration(seconds: 60);
    focusRegained = _never;
    focusGrace = const Duration(seconds: 1);
    _retryPrompt = null;
    _shownPrompt = null;
    _answered = false;
  }
}

/// Every request one [ArConnectPrompt.ask] has made. The first answer from
/// any of them is the answer; a failure counts only from the latest, since
/// Try again has given up on the ones before it.
class _Requests<T> {
  _Requests() {
    // A failure that arrives after the ask gave up has nobody to hear it.
    _answer.future.ignore();
  }

  final _answer = Completer<T>();
  int _latest = 0;

  bool get hasSettled => _answer.isCompleted;

  Future<T> get answer => _answer.future;

  /// Completes, never with an error, once there is an answer or a failure.
  late final Future<void> settled =
      _answer.future.then((_) {}, onError: (Object _) {});

  void send(Future<T> Function() request) {
    final number = ++_latest;
    Future<T> pending;
    try {
      pending = request();
    } catch (e, stackTrace) {
      pending = Future.error(e, stackTrace);
    }

    pending.then(
      (value) {
        if (!_answer.isCompleted) _answer.complete(value);
      },
      onError: (Object e, StackTrace stackTrace) {
        if (_answer.isCompleted) return;
        if (number != _latest) {
          logger.d('A Wander request given up on failed: $e');
          return;
        }
        _answer.completeError(e, stackTrace);
      },
    );
  }
}

class _ShownPrompt {
  _ShownPrompt(ArConnectRetryPrompt prompt, ArConnectUnavailableReason reason) {
    choice = prompt(reason, _closed.future);
  }

  final _closed = Completer<void>();
  late final Future<bool> choice;

  void close() {
    if (!_closed.isCompleted) _closed.complete();
  }
}

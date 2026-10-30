import 'dart:async';

import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:arweave/utils.dart' show ownerToAddress;
import 'package:flutter/foundation.dart';

/// Why Wander could not be asked for something.
enum ArConnectUnavailableReason {
  /// The extension is not in this browser.
  notInstalled,

  /// Wander was asked and did not answer in time, or its unlock window was
  /// closed. A locked Wander shows its unlock prompt, and Wander can also
  /// stop showing any prompt at all until the browser restarts.
  noAnswer,

  /// Wander no longer lets ArDrive in: it answered "Missing permission(s)".
  /// Wander forgets every site's permissions when it updates, so this is
  /// what a saved account meets after an update. Reconnecting fixes it.
  noPermission,
}

/// Whether [error], from a Wander call, says ArDrive no longer has its
/// permissions: `Missing permission(s) for "signDataItem": SIGN_TRANSACTION`.
bool isWanderMissingPermission(Object error) =>
    error is ArConnectMissingPermissionException ||
    RegExp(r'missing permission', caseSensitive: false)
        .hasMatch(error.toString());

/// Wander's permissions for ArDrive are not all there, found by asking for
/// them rather than by a call failing.
class ArConnectMissingPermissionException implements UntrackedException {
  const ArConnectMissingPermissionException();

  @override
  String toString() => 'ArConnectMissingPermissionException';
}

/// Whether [error] says Wander's unlock window was closed or cancelled.
///
/// Wander asks for its password before anything it is asked while locked,
/// and when that window goes away it fails the request with this. Nothing
/// was refused: the request never reached the person, so it is handled like
/// no answer. (A refused or cancelled prompt says "rejected" or
/// "AuthRequest".)
bool isWanderUnlockDismissed(Object error) =>
    error.toString().contains('User cancelled the operation');

/// Wander was reconnected, and is now on another wallet than the account
/// this device has saved.
class ArConnectWalletMismatchException implements UntrackedException {
  const ArConnectWalletMismatchException();

  @override
  String toString() => 'ArConnectWalletMismatchException';
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
/// Each request has a deadline. When it passes, Wander's unlock window is
/// closed, or the extension is missing, the registered
/// [ArConnectRetryPrompt] says so and offers Try again; Cancel (or no prompt
/// registered) ends in [ArConnectUnavailableException], which the write
/// handles like any other failure.
///
/// When Wander says ArDrive has lost its permissions, the same prompt
/// offers Reconnect instead: one `connect()` asking what sign-in asks, from
/// that click, then the request again. Never at startup: only a request that
/// failed finds out.
///
/// Wander's own prompt opens in a window of its own that ArDrive can't see.
/// When the person comes back to ArDrive while a request is still waiting
/// (see [tabFocus]), they most likely closed that window without
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

  /// True each time the ArDrive tab gets focus back or becomes visible
  /// again, false each time it loses focus or is hidden. Set by the app
  /// shell; nothing fires until then.
  static Stream<bool> Function() tabFocus = _never;

  /// How long a request may still take to answer once the person is back in
  /// ArDrive. Wander's window closing and its answer arriving race each
  /// other, and an answer on its way should not flash the prompt. Leaving
  /// ArDrive again within it, as when Wander's unlock window closes and its
  /// signature window opens, starts the wait over.
  static Duration focusGrace = const Duration(seconds: 1);

  static Stream<bool> _never() => const Stream.empty();

  static ArConnectRetryPrompt? _retryPrompt;
  static _ShownPrompt? _shownPrompt;
  static bool _answered = false;

  /// The reconnect running now, which every ask that chose Reconnect from
  /// the same prompt waits on, so Wander shows one connect window.
  static Future<bool>? _reconnecting;

  /// How many reconnects have succeeded. A missing-permission failure to a
  /// request sent before the latest one is stale: the request is sent again
  /// rather than the person asked again.
  static int _reconnects = 0;

  /// Told when a reconnect finds Wander on another wallet than the saved
  /// account's; see [registerOtherWalletHandler].
  static VoidCallback? _onOtherWallet;

  /// The saved account found to be on another wallet than Wander's. Nothing
  /// more is asked of Wander for it until the next sign-in ([signedIn]): a
  /// pass still running would otherwise sign with the other wallet.
  static String? _elsewhereFor;

  /// Whether the person chose Cancel on "Wander needs your permission
  /// again". Until they act again ([personActed]), a missing permission in
  /// a drive unlock pass ([quietAfterCancel]) ends the request without
  /// asking, so a pass, or the next one, doesn't bring the prompt back for
  /// each drive. Anything else the person does, a write above all, is
  /// always offered Reconnect.
  static bool _permissionDeclined = false;

  /// Marks the zone of a request made by a drive unlock pass.
  static final Object _passZoneKey = Object();

  /// Runs [request], made by a drive unlock pass that nobody asked for one
  /// drive at a time (discovery, or the other drives tried with an Unlock),
  /// so that after a Cancel on "Wander needs your permission again" it ends
  /// quietly instead of asking again.
  static Future<T> quietAfterCancel<T>(Future<T> Function() request) =>
      runZoned(request, zoneValues: {_passZoneKey: true});

  /// The person did something that needs Wander: Unlock, a sync they
  /// started, a write. A missing permission may ask them again.
  static void personActed() => _permissionDeclined = false;

  /// A sign-in starts over: Wander may be asked again for the account, and
  /// the person may be asked to reconnect.
  static void signedIn() {
    _elsewhereFor = null;
    _permissionDeclined = false;
  }

  /// Nothing more is asked of Wander for [savedPublicKey] until the next
  /// sign-in, because Wander is on another wallet.
  static void refuseFor(String savedPublicKey) =>
      _elsewhereFor = savedPublicKey;

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

  /// Makes [handler] the one told when a reconnect finds Wander on another
  /// wallet than the saved account's. Returns what removes it again.
  static VoidCallback registerOtherWalletHandler(VoidCallback handler) {
    _onOtherWallet = handler;
    return () {
      if (identical(_onOtherWallet, handler)) _onOtherWallet = null;
    };
  }

  /// [request]'s answer from [wander], asked again for as long as the person
  /// chooses Try again (or Reconnect). With [askPerson] false nobody is
  /// asked: the first failure throws, for checks that run in the background.
  ///
  /// [savedPublicKey] is the saved account's: after a reconnect, a Wander on
  /// any other wallet ends in [ArConnectWalletMismatchException] rather than
  /// the request.
  static Future<T> ask<T>(
    ArConnectService wander,
    Future<T> Function() request, {
    Duration? within,
    bool askPerson = true,
    String? savedPublicKey,
  }) async {
    var requests = _Requests<T>();
    var send = true;
    var sentAfter = _reconnects;

    while (true) {
      if (savedPublicKey != null && savedPublicKey == _elsewhereFor) {
        throw const ArConnectWalletMismatchException();
      }

      ArConnectUnavailableReason reason;
      if (!wander.isExtensionPresent()) {
        reason = ArConnectUnavailableReason.notInstalled;
      } else {
        if (send) {
          sentAfter = _reconnects;
          requests.send(request);
        }
        send = true;
        if (!requests.hasSettled) {
          await _waitForAnswer(
            requests.settled,
            within ?? readTimeout,
            // Coming back early only matters to someone who can be asked.
            watchFocus: askPerson && _retryPrompt != null,
          );
        }
        if (!requests.hasSettled) {
          reason = ArConnectUnavailableReason.noAnswer;
        } else {
          final failure = requests.failure;
          if (failure == null) return _answer(requests);
          if (isWanderMissingPermission(failure)) {
            reason = ArConnectUnavailableReason.noPermission;
          } else if (isWanderUnlockDismissed(failure)) {
            reason = ArConnectUnavailableReason.noAnswer;
          } else {
            return _answer(requests);
          }
          // That request is over; Try again or Reconnect sends a new one.
          requests = _Requests<T>();
        }
      }

      final prompt = _retryPrompt;
      if (!askPerson || prompt == null) {
        throw ArConnectUnavailableException(reason);
      }

      if (reason == ArConnectUnavailableReason.noPermission) {
        // Sent before a reconnect that has since succeeded: send it again.
        if (_reconnects != sentAfter) continue;

        // A reconnect is already running, from the person's click on an
        // earlier prompt: wait for it rather than prompting again.
        final running = _reconnecting;
        if (running != null) {
          if (await running && savedPublicKey != null) {
            await _checkSameWallet(wander, savedPublicKey);
          }
          continue;
        }

        if (_permissionDeclined && Zone.current[_passZoneKey] == true) {
          throw ArConnectUnavailableException(reason);
        }

        // Nothing is waiting on Wander here, so only the person closes this.
        if (!await _show(prompt, reason, null)) {
          _permissionDeclined = true;
          throw ArConnectUnavailableException(reason);
        }
        if (await _reconnect(wander) && savedPublicKey != null) {
          await _checkSameWallet(wander, savedPublicKey);
        }
        // Connected or not, the request says: if Wander still lets ArDrive
        // in, it answers; if not, the prompt shows again.
        continue;
      }

      final retry = await Future.any([
        _show(prompt, reason, requests.settled),
        requests.settled.then((_) => true),
      ]);
      if (requests.hasSettled) {
        // Answered, or failed, while the prompt was open: read that answer
        // rather than asking again.
        send = false;
        continue;
      }
      if (!retry) throw ArConnectUnavailableException(reason);
    }
  }

  /// Asks Wander for ArDrive's permissions again. True once it connected.
  ///
  /// Asks that chose Reconnect together share one connect, so Wander opens
  /// one window. It has a deadline like a signature: a Wander that shows
  /// nothing must not leave the prompt waiting.
  static Future<bool> _reconnect(ArConnectService wander) {
    final running = _reconnecting;
    if (running != null) return running;

    final reconnect = _connect(wander);
    _reconnecting = reconnect;
    reconnect.whenComplete(() {
      if (identical(_reconnecting, reconnect)) _reconnecting = null;
    });
    return reconnect;
  }

  static Future<bool> _connect(ArConnectService wander) async {
    try {
      await wander.connect().timeout(signTimeout);
      _answered = true;
      _reconnects++;
      return true;
    } catch (e) {
      logger.w('Wander did not reconnect: $e');
      return false;
    }
  }

  /// After a reconnect: the wallet Wander connected must be the saved
  /// account's, or nothing this account does can go through it.
  static Future<void> _checkSameWallet(
    ArConnectService wander,
    String savedPublicKey,
  ) async {
    final String connected;
    try {
      // The address, which Wander gives without its password.
      connected = await wander.getWalletAddress().timeout(readTimeout);
    } catch (e) {
      // The request that follows finds out what is wrong.
      logger.w('Could not read the wallet Wander reconnected: $e');
      return;
    }
    if (connected == await ownerToAddress(savedPublicKey)) return;

    logger.w('Wander reconnected on another wallet');
    refuseFor(savedPublicKey);
    _onOtherWallet?.call();
    throw const ArConnectWalletMismatchException();
  }

  static Future<T> _answer<T>(_Requests<T> requests) async {
    final answer = await requests.answer;
    _answered = true;
    return answer;
  }

  /// Until [settled], [within] passes, or, with [watchFocus], the person has
  /// been back in ArDrive for [focusGrace] without leaving again.
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
        ? tabFocus().listen((focused) {
            if (focused) {
              afterFocus ??= Timer(focusGrace, finish);
            } else {
              // Gone again, most likely to another Wander window.
              afterFocus?.cancel();
              afterFocus = null;
            }
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
  ///
  /// Prompts for different reasons are not shared: Try again is no answer to
  /// a missing permission. [settled] null leaves the prompt to the person.
  static Future<bool> _show(
    ArConnectRetryPrompt prompt,
    ArConnectUnavailableReason reason,
    Future<void>? settled,
  ) {
    final current = _shownPrompt;
    final shown = current != null && current.reason == reason
        ? current
        : _shownPrompt = _ShownPrompt(prompt, reason, (shown) {
            if (identical(_shownPrompt, shown)) _shownPrompt = null;
          });
    settled?.then((_) => shown.close());
    return shown.choice;
  }

  @visibleForTesting
  static void reset() {
    readTimeout = const Duration(seconds: 20);
    signTimeout = const Duration(seconds: 60);
    tabFocus = _never;
    focusGrace = const Duration(seconds: 1);
    _retryPrompt = null;
    _shownPrompt = null;
    _answered = false;
    _reconnecting = null;
    _reconnects = 0;
    _onOtherWallet = null;
    _elsewhereFor = null;
    _permissionDeclined = false;
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
  Object? _failure;

  bool get hasSettled => _answer.isCompleted;

  /// Why the request failed, once it has; null while waiting or answered.
  Object? get failure => _failure;

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
        _failure = e;
        _answer.completeError(e, stackTrace);
      },
    );
  }
}

/// The prompt on screen, shared by every ask that is waiting on it.
///
/// Its [choice] settles when the prompt answers, or at [close] with true,
/// whichever is first, and it lets go of the shared slot either way. So a
/// prompt that never answers, such as a dialog removed from under another
/// route, can't leave every later ask waiting on it.
class _ShownPrompt {
  _ShownPrompt(
    ArConnectRetryPrompt prompt,
    this.reason,
    this._onDone,
  ) {
    prompt(reason, _closed.future).then(_settle, onError: (Object e) {
      logger.w('The Wander prompt failed: $e');
      _settle(false);
    });
  }

  final ArConnectUnavailableReason reason;
  final void Function(_ShownPrompt) _onDone;
  final _closed = Completer<void>();
  final _choice = Completer<bool>();

  Future<bool> get choice => _choice.future;

  void _settle(bool retry) {
    if (_choice.isCompleted) return;
    _choice.complete(retry);
    _onDone(this);
  }

  /// Wander answered: the prompt is told to close, and anyone still waiting
  /// on it tries again.
  void close() {
    if (!_closed.isCompleted) _closed.complete();
    _settle(true);
  }
}

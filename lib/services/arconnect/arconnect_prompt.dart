import 'dart:async';

import 'package:ardrive/services/arconnect/arconnect.dart';
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
typedef ArConnectRetryPrompt = Future<bool> Function(
  ArConnectUnavailableReason reason,
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

  static ArConnectRetryPrompt? _retryPrompt;
  static Future<bool>? _shownPrompt;
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
    while (true) {
      final ArConnectUnavailableReason reason;
      if (!wander.isExtensionPresent()) {
        reason = ArConnectUnavailableReason.notInstalled;
      } else {
        try {
          final answer = await request().timeout(within ?? readTimeout);
          _answered = true;
          return answer;
        } on TimeoutException {
          reason = ArConnectUnavailableReason.noAnswer;
        }
      }

      final prompt = _retryPrompt;
      if (!askPerson || prompt == null || !await _show(prompt, reason)) {
        throw ArConnectUnavailableException(reason);
      }
    }
  }

  /// One prompt at a time: two requests that fail together share it.
  static Future<bool> _show(
    ArConnectRetryPrompt prompt,
    ArConnectUnavailableReason reason,
  ) {
    return _shownPrompt ??= prompt(reason).whenComplete(() {
      _shownPrompt = null;
    });
  }

  @visibleForTesting
  static void reset() {
    readTimeout = const Duration(seconds: 20);
    signTimeout = const Duration(seconds: 60);
    _retryPrompt = null;
    _shownPrompt = null;
    _answered = false;
  }
}

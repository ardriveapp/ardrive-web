import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/bridge_arns_owner_signer.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/domain/undername_validation.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/page_leaving/page_leaving.dart';
import 'package:ario_sdk/ario_sdk.dart';

/// Where a change is while it runs, for the progress line.
enum ArNSCommitStep {
  /// The ArNS wallet is asked to approve the change.
  approve,

  /// Turbo is making the change.
  working,

  /// Turbo wasn't a controller: the ArNS wallet approves its transaction.
  approveTransaction,

  /// Writing the name into the item's metadata.
  updatingDetails,
}

enum ArNSFailureKind {
  /// 402: not enough credits. Nothing was charged.
  insufficientCredits,

  /// A wallet prompt was rejected before anything was charged.
  rejected,

  /// The action expired after it was created; Turbo refunds the credits.
  expired,

  /// The action may have been created but the answer never came: never
  /// retried, the names are read again instead.
  lostAfterCreate,

  /// The connected wallet is on another account than the linked one.
  wrongAccount,

  /// Turbo or the chain said no before anything was charged.
  failed,
}

class ArNSChangeFailure implements Exception {
  const ArNSChangeFailure(this.kind, {this.refunded = false, this.cause});

  final ArNSFailureKind kind;

  /// For [ArNSFailureKind.expired]: whether Turbo said the credits came back
  /// already. Either way they come back within 15 minutes.
  final bool refunded;
  final Object? cause;

  @override
  String toString() => 'ArNSChangeFailure($kind, cause: $cause)';
}

/// Pays for and approves one record change: through Turbo with credits for a
/// name the ArNS wallet owns, with the wallet's own Solana transaction for a
/// name it manages for someone else (docs/NAMES.md, "Writes", Q23).
///
/// Never creates a Turbo action twice: anything that fails after the create
/// request was sent is [ArNSFailureKind.lostAfterCreate], expired or failed,
/// never retried here.
///
/// Remembers each action's nonce in [pending] the moment Turbo returns it,
/// before any further prompt, and forgets it once the action reaches an end
/// here, so a reload in between can say what became of it (docs/NAMES.md,
/// "Writes", steps 3 and 6).
class ArNSChangeExecutor {
  ArNSChangeExecutor({
    required TurboArNSActionClient client,
    required ArioSDK arioSDK,
    ArNSPendingActionStore? pending,
    String? Function()? profileAddress,
    DateTime Function()? clock,
    bool Function()? pageLeaving,
    Duration leaveGrace = const Duration(seconds: 1),
  })  : _client = client,
        _arioSDK = arioSDK,
        _pending = pending,
        _profileAddress = profileAddress,
        _clock = clock ?? DateTime.now,
        _pageLeaving = pageLeaving ?? pageIsLeaving,
        _leaveGrace = leaveGrace {
    if (pageLeaving == null) watchPageLeaving();
  }

  final TurboArNSActionClient _client;
  final ArioSDK _arioSDK;
  final ArNSPendingActionStore? _pending;
  final String? Function()? _profileAddress;
  final DateTime Function() _clock;

  /// Whether the page is being reloaded or closed.
  final bool Function() _pageLeaving;

  /// How long a declined second prompt waits to see whether the page is
  /// going, before its action is forgotten.
  final Duration _leaveGrace;

  Future<void> execute({
    required ArNSManagedName name,
    required ArNSRecordChange change,
    required ArNSOwnerSigner owner,
    required ArNSPayerSigner payer,
    List<String> paidBy = const [],
    required void Function(ArNSCommitStep step) onStep,
    void Function(String nonce)? onNonce,
  }) async {
    if (name.role == ArNSRole.controller) {
      return _asController(change, onStep);
    }

    final tracked = _TrackedOwner(owner);
    final trackedPayer = _TrackedPayer(payer);
    var created = false;
    String? nonce;
    onStep(ArNSCommitStep.approve);
    try {
      await _client.run(
        change,
        payer: trackedPayer,
        owner: tracked,
        paidBy: paidBy,
        onNonce: (result) async {
          created = true;
          nonce = result.nonce;
          await _remember(result.nonce, name, change);
          onNonce?.call(result.nonce);
          if (result is ArNSActionAwaitingSignature) {
            onStep(ArNSCommitStep.approveTransaction);
          } else {
            onStep(ArNSCommitStep.working);
          }
        },
      );
      await _forget(nonce);
    } on ArNSInsufficientCreditsException catch (e) {
      throw ArNSChangeFailure(ArNSFailureKind.insufficientCredits, cause: e);
    } on ArNSActionExpiredException catch (e) {
      await _forget(nonce);
      throw ArNSChangeFailure(
        ArNSFailureKind.expired,
        refunded: e.refunded,
        cause: e,
      );
    } on ArNSWrongAccountException catch (e) {
      if (created) await _forget(nonce);
      throw ArNSChangeFailure(
        created ? ArNSFailureKind.expired : ArNSFailureKind.wrongAccount,
        cause: e,
      );
    } on ArNSActionRequestException catch (e) {
      // Turbo answered. Before the action existed, nothing was charged.
      throw ArNSChangeFailure(
        created ? ArNSFailureKind.lostAfterCreate : ArNSFailureKind.failed,
        cause: e,
      );
    } catch (e) {
      logger.w('ArNS change failed: $e');
      if (created) {
        // The second prompt rejected or lost: the action expires unsigned and
        // its credits come back.
        if (tracked.signingTransaction) {
          // Declined, it can only expire, and the dialog says the credits
          // come back now: forgotten, so the next load doesn't say it again.
          // A reload aborts the prompt with the same kind of error before
          // the page goes, and signed then lost it may have landed: kept
          // either way, so the next load reads how it ended.
          if (!tracked.signedTransaction) {
            unawaited(_forgetUnlessLeaving(nonce));
          }
          throw ArNSChangeFailure(ArNSFailureKind.expired, cause: e);
        }
        throw ArNSChangeFailure(ArNSFailureKind.lostAfterCreate, cause: e);
      }
      if (trackedPayer.signed) {
        // The request went out and no answer came back: it may exist.
        throw ArNSChangeFailure(ArNSFailureKind.lostAfterCreate, cause: e);
      }
      throw ArNSChangeFailure(ArNSFailureKind.rejected, cause: e);
    }
  }

  /// Persists the action before any further prompt. A store that fails is
  /// logged, not fatal: the action is paid for, and stopping now would only
  /// let it expire.
  Future<void> _remember(
    String nonce,
    ArNSManagedName name,
    ArNSRecordChange change,
  ) async {
    final pending = _pending;
    final profile = _profileAddress?.call();
    if (pending == null || profile == null) return;
    final literal = literalArNSName(change.undername, name.name);
    try {
      await pending.add(
        profile,
        ArNSPendingAction(
          nonce: nonce,
          paymentUrl: _client.paymentUrl,
          name: literal,
          description: switch (change) {
            ArNSSetRecord(:final transactionId) =>
              '${change.action.path} $literal -> $transactionId',
            ArNSRemoveRecord() => '${change.action.path} $literal',
          },
          createdAt: _clock(),
        ),
      );
    } catch (e) {
      logger.w('Could not remember ArNS action $nonce: $e');
    }
  }

  /// Forgets a declined action once it is clear the page is staying: a
  /// page that goes never gets this far, and one going keeps it.
  Future<void> _forgetUnlessLeaving(String? nonce) async {
    if (_pageLeaving()) return;
    await Future<void>.delayed(_leaveGrace);
    if (_pageLeaving()) return;
    await _forget(nonce);
  }

  /// Forgets an action that reached an end here: done, or expired.
  Future<void> _forget(String? nonce) async {
    final pending = _pending;
    final profile = _profileAddress?.call();
    if (pending == null || profile == null || nonce == null) return;
    try {
      await pending.remove(profile, nonce);
    } catch (e) {
      logger.w('Could not forget ArNS action $nonce: $e');
    }
  }

  Future<void> _asController(
    ArNSRecordChange change,
    void Function(ArNSCommitStep) onStep,
  ) async {
    onStep(ArNSCommitStep.approve);
    try {
      switch (change) {
        case ArNSSetRecord():
          await _arioSDK.setRecordAsController(
            processId: change.antId,
            undername: change.undername,
            transactionId: change.transactionId,
            ttlSeconds: change.ttlSeconds,
          );
        case ArNSRemoveRecord():
          await _arioSDK.removeRecordAsController(
            processId: change.antId,
            undername: change.undername,
          );
      }
    } catch (e) {
      // The wallet signs and sends its own transaction: a rejection or a
      // failed send costs nothing but, at most, its fee.
      logger.w('ArNS controller change failed: $e');
      throw ArNSChangeFailure(ArNSFailureKind.rejected, cause: e);
    }
  }
}

class _TrackedOwner implements ArNSOwnerSigner {
  _TrackedOwner(this._inner);

  final ArNSOwnerSigner _inner;
  bool signingTransaction = false;
  bool signedTransaction = false;

  @override
  String get address => _inner.address;

  @override
  Future<Uint8List> signMessage(Uint8List message) =>
      _inner.signMessage(message);

  @override
  Future<String> signTransaction(String transactionBase64) async {
    signingTransaction = true;
    final signed = await _inner.signTransaction(transactionBase64);
    signedTransaction = true;
    return signed;
  }
}

class _TrackedPayer implements ArNSPayerSigner {
  _TrackedPayer(this._inner);

  final ArNSPayerSigner _inner;
  bool signed = false;

  @override
  Future<Map<String, String>> signedRequestHeaders(String nonce) async {
    final headers = await _inner.signedRequestHeaders(nonce);
    signed = true;
    return headers;
  }
}

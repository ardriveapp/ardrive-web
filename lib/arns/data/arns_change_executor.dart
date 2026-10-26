import 'dart:typed_data';

import 'package:ardrive/arns/data/bridge_arns_owner_signer.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/utils/logger.dart';
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
class ArNSChangeExecutor {
  ArNSChangeExecutor({
    required TurboArNSActionClient client,
    required ArioSDK arioSDK,
  })  : _client = client,
        _arioSDK = arioSDK;

  final TurboArNSActionClient _client;
  final ArioSDK _arioSDK;

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
    onStep(ArNSCommitStep.approve);
    try {
      await _client.run(
        change,
        payer: trackedPayer,
        owner: tracked,
        paidBy: paidBy,
        onNonce: (result) {
          created = true;
          onNonce?.call(result.nonce);
          if (result is ArNSActionAwaitingSignature) {
            onStep(ArNSCommitStep.approveTransaction);
          } else {
            onStep(ArNSCommitStep.working);
          }
        },
      );
    } on ArNSInsufficientCreditsException catch (e) {
      throw ArNSChangeFailure(ArNSFailureKind.insufficientCredits, cause: e);
    } on ArNSActionExpiredException catch (e) {
      throw ArNSChangeFailure(
        ArNSFailureKind.expired,
        refunded: e.refunded,
        cause: e,
      );
    } on ArNSWrongAccountException catch (e) {
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

  @override
  String get address => _inner.address;

  @override
  Future<Uint8List> signMessage(Uint8List message) =>
      _inner.signMessage(message);

  @override
  Future<String> signTransaction(String transactionBase64) {
    signingTransaction = true;
    return _inner.signTransaction(transactionBase64);
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

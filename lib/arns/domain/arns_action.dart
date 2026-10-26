import 'package:equatable/equatable.dart';

/// The Turbo ArNS actions ArDrive uses (docs/NAMES.md, "Writes").
enum ArNSRecordAction {
  setRecord('set-record'),
  removeRecord('remove-record');

  const ArNSRecordAction(this.path);

  /// The action's name in Turbo's routes and in the owner proof.
  final String path;
}

/// One record change for Turbo to make on an ANT.
sealed class ArNSRecordChange extends Equatable {
  const ArNSRecordChange({required this.antId, required this.undername});

  final String antId;

  /// The undername, or `@` for the name itself.
  final String undername;

  ArNSRecordAction get action;

  /// The fields of the owner proof, in the order Turbo rebuilds them.
  List<String> get proofFields;

  /// The create body, without `ownerAddress`.
  Map<String, Object> get body;
}

class ArNSSetRecord extends ArNSRecordChange {
  const ArNSSetRecord({
    required super.antId,
    required super.undername,
    required this.transactionId,
    required this.ttlSeconds,
  });

  final String transactionId;

  /// Always sent: Turbo's own default is 3600.
  final int ttlSeconds;

  @override
  ArNSRecordAction get action => ArNSRecordAction.setRecord;

  @override
  List<String> get proofFields =>
      [antId, undername, transactionId, ttlSeconds.toString()];

  @override
  Map<String, Object> get body => {
        'antId': antId,
        'transactionId': transactionId,
        'undername': undername,
        'ttlSeconds': ttlSeconds,
      };

  @override
  List<Object?> get props => [antId, undername, transactionId, ttlSeconds];
}

class ArNSRemoveRecord extends ArNSRecordChange {
  const ArNSRemoveRecord({required super.antId, required super.undername});

  @override
  ArNSRecordAction get action => ArNSRecordAction.removeRecord;

  @override
  List<String> get proofFields => [antId, undername];

  @override
  Map<String, Object> get body => {'antId': antId, 'undername': undername};

  @override
  List<Object?> get props => [antId, undername];
}

/// An action's state as Turbo reports it. Branch on the type, never on which
/// action was asked for: the same action can come back either way.
sealed class ArNSActionResult extends Equatable {
  const ArNSActionResult({required this.nonce, required this.action});

  /// The idempotency key. Persist it before any further prompt.
  final String nonce;
  final String action;

  factory ArNSActionResult.fromJson(Map<String, dynamic> json) {
    final nonce = json['nonce'] as String;
    final action = json['action'] as String? ?? '';
    final status = json['status'] as String?;

    if (json['failedDate'] != null || status == 'failed') {
      return ArNSActionFailed(
        nonce: nonce,
        action: action,
        failedDate: json['failedDate'] as String?,
      );
    }

    return switch (status) {
      'completed' => ArNSActionCompleted(
          nonce: nonce,
          action: action,
          messageId: json['messageId'] as String?,
          antId: json['antId'] as String?,
          alreadyCompleted: json['alreadyCompleted'] == true,
        ),
      // A status read may leave the transaction out: then it can't be
      // signed from here, and is reported rather than guessed at.
      'awaiting-signature' when json['transaction'] is String =>
        ArNSActionAwaitingSignature(
          nonce: nonce,
          action: action,
          transaction: json['transaction'] as String,
          lastValidBlockHeight: json['lastValidBlockHeight']?.toString(),
          expiresAt: json['expiresAt'] as String?,
        ),
      _ => ArNSActionInProgress(
          nonce: nonce,
          action: action,
          status: status ?? '',
        ),
    };
  }
}

class ArNSActionCompleted extends ArNSActionResult {
  const ArNSActionCompleted({
    required super.nonce,
    required super.action,
    this.messageId,
    this.antId,
    this.alreadyCompleted = false,
  });

  /// The Solana transaction of the on-chain write.
  final String? messageId;
  final String? antId;

  /// A replayed sign of an action that had already landed.
  final bool alreadyCompleted;

  @override
  List<Object?> get props => [nonce, action, messageId, antId];
}

/// Turbo is not a controller of the name: the ArNS wallet signs
/// [transaction] as is, within about 30 seconds.
class ArNSActionAwaitingSignature extends ArNSActionResult {
  const ArNSActionAwaitingSignature({
    required super.nonce,
    required super.action,
    required this.transaction,
    this.lastValidBlockHeight,
    this.expiresAt,
  });

  /// Base64, already signed by Turbo as fee payer.
  final String transaction;
  final String? lastValidBlockHeight;

  /// When Turbo refunds an action never completed: not the signing deadline.
  final String? expiresAt;

  @override
  List<Object?> get props => [nonce, action, transaction];
}

class ArNSActionFailed extends ArNSActionResult {
  const ArNSActionFailed({
    required super.nonce,
    required super.action,
    this.failedDate,
  });

  final String? failedDate;

  @override
  List<Object?> get props => [nonce, action, failedDate];
}

/// A status this client does not know, reported rather than guessed at.
class ArNSActionInProgress extends ArNSActionResult {
  const ArNSActionInProgress({
    required super.nonce,
    required super.action,
    required this.status,
  });

  final String status;

  @override
  List<Object?> get props => [nonce, action, status];
}

sealed class ArNSActionException implements Exception {
  const ArNSActionException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// 402: the paying wallet has too few credits. Nothing was debited.
class ArNSInsufficientCreditsException extends ArNSActionException {
  const ArNSInsufficientCreditsException(super.message);
}

/// The action expired before its transaction landed.
class ArNSActionExpiredException extends ArNSActionException {
  const ArNSActionExpiredException(
    super.message, {
    required this.nonce,
    required this.refunded,
  });

  final String nonce;

  /// Whether Turbo's response said the credits came back. False means it
  /// did not say; Turbo refunds an abandoned action within 15 minutes.
  final bool refunded;
}

/// 503 "Blockhash not found": expiry could not be proven. Re-post the same
/// signed bytes; never create the action again.
class ArNSBlockhashNotFoundException extends ArNSActionException {
  const ArNSBlockhashNotFoundException(super.message, {required this.nonce});

  final String nonce;
}

/// Any other failed request.
class ArNSActionRequestException extends ArNSActionException {
  const ArNSActionRequestException(super.message, {required this.statusCode});

  final int statusCode;
}

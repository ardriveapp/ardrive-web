import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'pending_transaction.g.dart';

/// A pending cryptocurrency transaction that can be recovered.
///
/// Stored locally to allow users to recover credits if they close the app
/// before the transaction is confirmed.
@JsonSerializable()
class PendingCryptoTransaction extends Equatable {
  /// Blockchain transaction ID (tx hash)
  final String transactionId;

  /// Token type used for payment
  @JsonKey(fromJson: _tokenFromJson, toJson: _tokenToJson)
  final CryptoToken token;

  /// Amount paid in smallest unit (wei, lamports, mARIO, etc.)
  final String tokenAmountRaw;

  /// The Arweave address that should receive credits
  final String arweaveAddress;

  /// When the transaction was created
  final DateTime createdAt;

  /// Expected credits to receive
  final double? expectedCredits;

  /// USD value at time of transaction
  final double? usdValue;

  const PendingCryptoTransaction({
    required this.transactionId,
    required this.token,
    required this.tokenAmountRaw,
    required this.arweaveAddress,
    required this.createdAt,
    this.expectedCredits,
    this.usdValue,
  });

  /// Token amount as BigInt
  BigInt get tokenAmount => BigInt.parse(tokenAmountRaw);

  /// Human-readable token amount
  double get tokenAmountDisplay {
    final divisor = switch (token.decimals) {
      6 => 1e6,
      9 => 1e9,
      18 => 1e18,
      _ => 1e6,
    };
    return tokenAmount.toDouble() / divisor;
  }

  /// Formatted token amount with symbol
  String get formattedAmount =>
      '${tokenAmountDisplay.toStringAsFixed(4)} ${token.symbol}';

  /// Whether this transaction is considered stale (older than 24 hours)
  bool get isStale =>
      DateTime.now().difference(createdAt) > const Duration(hours: 24);

  /// Age of the transaction
  Duration get age => DateTime.now().difference(createdAt);

  /// Human-readable age string
  String get ageText {
    final minutes = age.inMinutes;
    if (minutes < 60) {
      return '$minutes min ago';
    }
    final hours = age.inHours;
    if (hours < 24) {
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    }
    return '${age.inDays} day${age.inDays == 1 ? '' : 's'} ago';
  }

  factory PendingCryptoTransaction.fromJson(Map<String, dynamic> json) =>
      _$PendingCryptoTransactionFromJson(json);

  Map<String, dynamic> toJson() => _$PendingCryptoTransactionToJson(this);

  /// Create from payment parameters
  factory PendingCryptoTransaction.create({
    required String transactionId,
    required CryptoToken token,
    required BigInt tokenAmount,
    required String arweaveAddress,
    double? expectedCredits,
    double? usdValue,
  }) {
    return PendingCryptoTransaction(
      transactionId: transactionId,
      token: token,
      tokenAmountRaw: tokenAmount.toString(),
      arweaveAddress: arweaveAddress,
      createdAt: DateTime.now(),
      expectedCredits: expectedCredits,
      usdValue: usdValue,
    );
  }

  @override
  List<Object?> get props => [
        transactionId,
        token,
        tokenAmountRaw,
        arweaveAddress,
        createdAt,
        expectedCredits,
        usdValue,
      ];

  @override
  String toString() {
    return 'PendingCryptoTransaction{txId: $transactionId, token: $token, '
        'amount: $formattedAmount, created: $createdAt}';
  }
}

// JSON serialization helpers for CryptoToken enum
String _tokenToJson(CryptoToken token) => token.name;

CryptoToken _tokenFromJson(String name) {
  return CryptoToken.values.firstWhere(
    (t) => t.name == name,
    orElse: () => CryptoToken.arioAO,
  );
}

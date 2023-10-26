import 'package:equatable/equatable.dart';

final txIdRegex = RegExp(r'^(\w|-){43}$');

class TransactionID extends Equatable {
  final String _txId;

  TransactionID(String transactionId) : _txId = transactionId {
    if (!txIdRegex.hasMatch(transactionId)) {
      throw const InvalidTransactionId();
    }
  }

  @override
  String toString() {
    return _txId;
  }

  @override
  List<Object?> get props => [_txId];
}

class InvalidTransactionId implements Exception {
  static const String _errorMessage =
      'Transaction ID should be a 43-character, alphanumeric string potentially including "=" and "_" characters.';

  const InvalidTransactionId();

  @override
  String toString() {
    return _errorMessage;
  }
}

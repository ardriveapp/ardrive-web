class ArDriveDecryptionException implements Exception {
  final String? corruptedDataAppVersion;
  final String? corruptedTransactionId;

  ArDriveDecryptionException({
    this.corruptedDataAppVersion,
    this.corruptedTransactionId,
  });

  @override
  String toString() {
    return 'ArDriveDecryptionException: corruptedDataAppVersion: $corruptedDataAppVersion and corruptedTransactionId: $corruptedTransactionId';
  }
}

class TransactionDecryptionException extends ArDriveDecryptionException {
  TransactionDecryptionException({
    super.corruptedDataAppVersion,
    super.corruptedTransactionId,
  });

  @override
  String toString() {
    return 'TransactionDecryptionException: corruptedDataAppVersion: $corruptedDataAppVersion and corruptedTransactionId: $corruptedTransactionId';
  }
}

class MissingCipherTagException extends ArDriveDecryptionException {
  MissingCipherTagException({
    super.corruptedDataAppVersion,
    super.corruptedTransactionId,
  });

  @override
  String toString() {
    return 'MissingCipherTagException: corruptedDataAppVersion: $corruptedDataAppVersion and corruptedTransactionId: $corruptedTransactionId';
  }
}

class UnknownCipherException extends ArDriveDecryptionException {
  UnknownCipherException({
    super.corruptedDataAppVersion,
    super.corruptedTransactionId,
  });

  @override
  String toString() {
    return 'UnknowCipherException: corruptedDataAppVersion: $corruptedDataAppVersion and corruptedTransactionId: $corruptedTransactionId';
  }
}

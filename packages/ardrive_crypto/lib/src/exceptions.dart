class ArDriveDecryptionException implements Exception {
  final String? corruptedDataAppVersion;

  ArDriveDecryptionException({this.corruptedDataAppVersion});

  @override
  String toString() {
    return 'ARFSDecryptionException: corruptedDataAppVersion: $corruptedDataAppVersion';
  }
}

class TransactionDecryptionException extends ArDriveDecryptionException {
  TransactionDecryptionException({super.corruptedDataAppVersion});

  @override
  String toString() {
    return 'TransactionDecryptionException: corruptedDataAppVersion: $corruptedDataAppVersion';
  }
}

class MissingCipherTagException extends ArDriveDecryptionException {
  MissingCipherTagException({super.corruptedDataAppVersion});

  @override
  String toString() {
    return 'MissingCipherTagException: corruptedDataAppVersion: $corruptedDataAppVersion';
  }
}

class UnknownCipherException extends ArDriveDecryptionException {
  UnknownCipherException({super.corruptedDataAppVersion});

  @override
  String toString() {
    return 'UnknowCipherException: corruptedDataAppVersion: $corruptedDataAppVersion';
  }
}

import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_logger/ardrive_logger.dart';

final logger = Logger(
  logLevel: LogLevel.debug,
  storeLogsInMemory: true,
  logExporter: LogExporter(),
  shouldLogErrorCallback: shouldLogErrorCallback,
);

final Set<String> _knownTransactionDecryptionBugVersions = {
  '2.30.0',
  '2.30.1',
  '2.30.2',
  '2.36.0',
  '2.37.0',
  '2.37.1'
};

ShouldLogErrorCallback shouldLogErrorCallback = (error) {
  if (error is ActionCanceledException) {
    return false;
  } else if (error is TransactionDecryptionException) {
    return !_knownTransactionDecryptionBugVersions
        .contains(error.corruptedDataAppVersion);
  }
  return true;
};

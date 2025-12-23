import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:arweave/arweave.dart';

final logger = Logger(
  logLevel: LogLevel.debug,
  storeLogsInMemory: true,
  logExporter: LogExporter(),
  shouldLogErrorCallback: shouldLogErrorCallback,
);

/// Callback for logging wallet signature operations.
/// This is passed to wallet instances to log when sign() or signDataItem() is called.
void walletSignCallback(String message, String? context) {
  logger.d('WalletSign: $message${context != null ? ' [context: $context]' : ''}');
}

/// The SignCallback type from arweave-dart for wallet signing operations.
SignCallback get walletOnSign => walletSignCallback;

final Set<String> _knownTransactionDecryptionBugVersions = {
  '2.30.0',
  '2.30.1',
  '2.30.2',
  '2.32.0',
  '2.36.0',
  '2.37.0',
  '2.37.1',
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

// Stub implementation for non-web platforms

/// Whether the SDK is loaded and ready to use
bool get isTurboSDKLoaded => false;

/// Error message if SDK failed to load
String? get turboSDKError => 'Turbo SDK is only available on web platforms';

/// Create an unauthenticated Turbo client
Future<Object> createUnauthenticatedTurbo({
  String? gatewayUrl,
  String? paymentServiceUrl,
  String? uploadServiceUrl,
  String? token,
}) async {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

/// Create an authenticated Turbo client with a signer
Future<Object> createAuthenticatedTurbo({
  required Object signer,
  String? gatewayUrl,
  String? paymentServiceUrl,
  String? uploadServiceUrl,
  String? token,
}) async {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

/// Create an authenticated Turbo client with a wallet adapter
Future<Object> createAuthenticatedTurboWithWalletAdapter({
  required Object ethersSigner,
  String? gatewayUrl,
  String? paymentServiceUrl,
  String? uploadServiceUrl,
  required String token,
}) async {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

/// Create an authenticated Turbo client with a Solana wallet adapter
Future<Object> createAuthenticatedTurboWithSolanaAdapter({
  required Object solanaWalletAdapter,
  String? gatewayUrl,
  String? paymentServiceUrl,
  String? uploadServiceUrl,
}) async {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

/// Get winc for a token amount
Future<BigInt> getWincForToken(Object turboClient, Object tokenAmount) async {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

/// Execute top up with tokens
Future<Object> topUpWithTokens(
  Object turboClient,
  Object tokenAmount, {
  Object? feeMultiplier,
  String? destinationAddress,
}) async {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

/// Get the user's Turbo balance
Future<BigInt> getTurboBalance(Object turboClient) async {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

/// Submit a fund transaction for retry/recovery
Future<Object> submitFundTransaction(
    Object turboClient, String transactionId) async {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

/// Convert token amounts using SDK helpers
Object convertARToTokenAmount(double amount) {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

Object convertARIOToTokenAmount(double amount) {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

Object convertETHToTokenAmount(double amount) {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

Object convertSOLToTokenAmount(double amount) {
  throw UnsupportedError('Turbo SDK is only available on web platforms');
}

/// Stub classes for type compatibility

class ArconnectSignerJS {
  ArconnectSignerJS(Object arweaveWallet) {
    throw UnsupportedError('Turbo SDK is only available on web platforms');
  }
}

class InjectedEthereumSignerJS {
  InjectedEthereumSignerJS(Object provider) {
    throw UnsupportedError('Turbo SDK is only available on web platforms');
  }

  Object? get publicKey => null;
  set publicKey(Object? value) {}
}

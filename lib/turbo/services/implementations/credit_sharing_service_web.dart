import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/turbo_sdk_interop.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/utils/logger.dart';

/// Moves the spending right, not the credits.
///
/// Signing in with Phantom derives a deterministic Arweave wallet, and that
/// derived address is what ArDrive bills. Credits bought in Turbo's own console
/// against the Solana wallet sit on a different Turbo account, and no amount of
/// asking from the Arweave side can reach them: an approval is the holder's
/// decision, so it has to be signed by the holder.
///
/// That is the whole job here. Connect the wallet the reader signed in with,
/// authenticate Turbo *as that wallet*, and have it approve the derived address.
/// Afterwards nothing else needs to change: the balance endpoint reports the
/// approval in `receivedApprovals`, and uploads already send `x-paid-by`.
class CreditSharingService {
  CreditSharingService({
    required SolanaWalletService solanaWalletService,
    required String paymentServiceUrl,
  })  : _solanaWalletService = solanaWalletService,
        _paymentServiceUrl = paymentServiceUrl;

  final SolanaWalletService _solanaWalletService;
  final String _paymentServiceUrl;

  final WalletSignerCache _signerCache = WalletSignerCache();

  /// Builds one from app config, the way the rest of the crypto stack is put
  /// together: at the point of use rather than held in a provider. See
  /// `crypto_payment_option.dart`, which assembles its services the same way.
  factory CreditSharingService.fromConfig(ConfigService configService) {
    final config = configService.config;
    final networkConfig = CryptoNetworkConfig.fromEnvironment(
      config.useTurboUpload ? 'production' : 'development',
      arweaveGatewayUrl: config.arweaveGatewayUrl ?? defaultGraphqlGateway,
      turboUploadUrl: config.defaultTurboUploadUrl,
      turboPaymentUrl: config.defaultTurboPaymentUrl,
    );

    return CreditSharingService(
      solanaWalletService: SolanaWalletService(networkConfig: networkConfig),
      paymentServiceUrl: config.defaultTurboPaymentUrl!,
    );
  }

  bool get isSupported => true;

  /// Grants [approvedAddress] the right to spend [approvedWinc] of the sign-in
  /// wallet's credits.
  ///
  /// Prompts the wallet extension, so it is only ever called from a control the
  /// reader pressed. Reconnects first when the extension has dropped the
  /// session, which it does routinely between page loads: the sign-in signature
  /// happened once, long ago, and nothing has held the connection open since.
  ///
  /// Throws on refusal or failure. The caller is expected to fall back to
  /// telling the reader where their credits are, which is what the sheet said
  /// before this control existed.
  Future<void> shareCreditsFromSignInWallet({
    required String approvedAddress,
    required BigInt approvedWinc,
  }) async {
    if (!_solanaWalletService.isConnected) {
      logger.d('Reconnecting the sign-in wallet to sign a credit approval');
      await _solanaWalletService.connect();
    }

    final adapter =
        await _signerCache.getOrCreateSolanaSigner(_solanaWalletService);

    // Authenticated as the wallet that *holds* the credits. A client built for
    // the derived Arweave wallet could ask for this all day and be refused, and
    // rightly: it is not that account's grant to make.
    final turbo = await createAuthenticatedTurboWithSolanaAdapter(
      solanaWalletAdapter: adapter,
      paymentServiceUrl: _paymentServiceUrl,
    );

    await shareCredits(
      turbo,
      approvedAddress: approvedAddress,
      approvedWinc: approvedWinc,
    );

    logger.i('Shared credits with the derived Arweave wallet');
  }
}

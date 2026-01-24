import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/services/crypto_payment_service.dart';
import 'package:ardrive/turbo/services/crypto_price_service.dart';
import 'package:ardrive/turbo/services/crypto_transaction_storage.dart';
import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/crypto_topup.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A styled banner that offers crypto payment as an alternative to card payment.
///
/// Matches the ArDrive UI style with proper theming and hover states.
class CryptoPaymentOption extends StatefulWidget {
  /// Called before opening the crypto modal (e.g., to close the current modal)
  final VoidCallback? onBeforeOpen;

  const CryptoPaymentOption({
    super.key,
    this.onBeforeOpen,
  });

  @override
  State<CryptoPaymentOption> createState() => _CryptoPaymentOptionState();
}

class _CryptoPaymentOptionState extends State<CryptoPaymentOption> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openCryptoModal(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered
                ? colors.themeBgSubtle
                : colors.themeBgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? colors.themeFgMuted
                  : colors.themeBorderDefault,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Crypto icon container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.themeBgSubtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: _CryptoIconStack(),
                ),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pay with Crypto',
                      style: ArDriveTypographyNew.of(context).paragraphLarge(
                        fontWeight: ArFontWeight.bold,
                        color: colors.themeFgDefault,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ETH, USDC, SOL, or ARIO',
                      style: ArDriveTypographyNew.of(context).paragraphSmall(
                        color: colors.themeFgMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow icon
              ArDriveIcons.carretRight(
                size: 20,
                color: colors.themeFgMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCryptoModal(BuildContext context) async {
    // Get necessary dependencies before any async operations
    final auth = context.read<ArDriveAuth>();
    final configService = context.read<ConfigService>();
    final navigator = Navigator.of(context);
    final themeColors = ArDriveTheme.of(context).themeData.colors;

    // Call onBeforeOpen callback if provided (e.g., to notify parent)
    widget.onBeforeOpen?.call();

    // Close the current modal first (only if we can pop)
    if (navigator.canPop()) {
      navigator.pop();
    }

    // Small delay to let the modal close animation complete
    await Future.delayed(const Duration(milliseconds: 100));

    // Determine environment for network config
    final environment =
        configService.config.useTurboUpload ? 'production' : 'development';
    final networkConfig = CryptoNetworkConfig.fromEnvironment(environment);

    // Create the HTTP client
    final httpClient = ArDriveHTTP();

    // Create the signer cache
    final signerCache = WalletSignerCache();

    // Create price service for real-time gas estimation
    final priceService = CryptoPriceService(httpClient: httpClient);

    // Create the crypto topup services
    final cryptoPaymentService = CryptoPaymentService(
      networkConfig: networkConfig,
      httpClient: httpClient,
      signerCache: signerCache,
      priceService: priceService,
    );

    final ethereumWalletService = EthereumWalletService(
      networkConfig: networkConfig,
      getTokenPrice: priceService.getUsdPrice,
    );
    final solanaWalletService =
        SolanaWalletService(networkConfig: networkConfig);

    // Get SharedPreferences for transaction storage
    final prefs = await SharedPreferences.getInstance();
    final transactionStorage = CryptoTransactionStorage(prefs);

    // Create the BLoC
    final bloc = CryptoTopupBloc(
      paymentService: cryptoPaymentService,
      ethereumWalletService: ethereumWalletService,
      solanaWalletService: solanaWalletService,
      signerCache: signerCache,
      transactionStorage: transactionStorage,
      arweaveWalletAddress: auth.currentUser.walletAddress,
    );

    // Initialize the BLoC
    bloc.add(const CryptoTopupStarted());

    // Show the crypto modal
    if (context.mounted) {
      await showArDriveDialog(
        context,
        content: BlocProvider.value(
          value: bloc,
          child: const CryptoTopupModal(),
        ),
        barrierDismissible: false,
        barrierColor: themeColors.shadow.withOpacity(0.9),
      );
    }

    // Clean up when modal is closed (single cleanup point)
    bloc.close();
    ethereumWalletService.dispose();
    solanaWalletService.dispose();
  }
}

/// Stack of crypto currency icons for visual appeal
class _CryptoIconStack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    // Simple icon representation using text symbols
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ETH symbol
        Text(
          'Ξ',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colors.themeFgDefault,
          ),
        ),
        const SizedBox(width: 2),
        // Dollar sign for USDC
        Text(
          '\$',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: colors.themeFgMuted,
          ),
        ),
      ],
    );
  }
}

/// Divider with "OR" text for separating payment methods
class PaymentMethodDivider extends StatelessWidget {
  const PaymentMethodDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: colors.themeBorderDefault,
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'OR',
              style: ArDriveTypographyNew.of(context).paragraphSmall(
                fontWeight: ArFontWeight.bold,
                color: colors.themeFgMuted,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: colors.themeBorderDefault,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the crypto topup modal directly.
///
/// This is a convenience function for showing the crypto modal from anywhere.
Future<void> showCryptoTopupModalStandalone(
  BuildContext context, {
  Function()? onSuccess,
}) async {
  final auth = context.read<ArDriveAuth>();
  final configService = context.read<ConfigService>();
  final themeColors = ArDriveTheme.of(context).themeData.colors;

  // Determine environment for network config
  final environment =
      configService.config.useTurboUpload ? 'production' : 'development';
  final networkConfig = CryptoNetworkConfig.fromEnvironment(environment);

  // Create the HTTP client
  final httpClient = ArDriveHTTP();

  // Create the signer cache
  final signerCache = WalletSignerCache();

  // Create price service for real-time gas estimation
  final priceService = CryptoPriceService(httpClient: httpClient);

  // Create the crypto topup services
  final cryptoPaymentService = CryptoPaymentService(
    networkConfig: networkConfig,
    httpClient: httpClient,
    signerCache: signerCache,
    priceService: priceService,
  );

  final ethereumWalletService = EthereumWalletService(
    networkConfig: networkConfig,
    getTokenPrice: priceService.getUsdPrice,
  );
  final solanaWalletService = SolanaWalletService(networkConfig: networkConfig);

  // Get SharedPreferences for transaction storage
  final prefs = await SharedPreferences.getInstance();
  final transactionStorage = CryptoTransactionStorage(prefs);

  // Create the BLoC
  final bloc = CryptoTopupBloc(
    paymentService: cryptoPaymentService,
    ethereumWalletService: ethereumWalletService,
    solanaWalletService: solanaWalletService,
    signerCache: signerCache,
    transactionStorage: transactionStorage,
    arweaveWalletAddress: auth.currentUser.walletAddress,
  );

  // Initialize the BLoC
  bloc.add(const CryptoTopupStarted());

  // Show the crypto modal
  if (context.mounted) {
    await showArDriveDialog(
      context,
      content: BlocProvider.value(
        value: bloc,
        child: const CryptoTopupModal(),
      ),
      barrierDismissible: false,
      barrierColor: themeColors.shadow.withOpacity(0.9),
    );
  }

  // Check if payment was successful
  final currentState = bloc.state;
  if (currentState is CryptoTopupSuccess) {
    onSuccess?.call();
  }

  // Clean up (single cleanup point)
  bloc.close();
  ethereumWalletService.dispose();
  solanaWalletService.dispose();
}

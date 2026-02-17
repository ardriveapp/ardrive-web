import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/turbo/services/crypto_payment_service.dart';
import 'package:ardrive/turbo/services/crypto_price_service.dart';
import 'package:ardrive/turbo/services/crypto_transaction_storage.dart';
import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_confirmation_view.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_processing_view.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_result_view.dart';
import 'package:ardrive/turbo/topup/views/unified/inline_crypto_payment.dart';
import 'package:ardrive/turbo/topup/views/unified/wallet_connection_view.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified crypto payment flow that can be embedded in the main top-up dialog.
///
/// This provides a streamlined 3-step flow:
/// 1. Token selection + wallet connection (inline)
/// 2. Confirmation
/// 3. Success/Error
///
/// The fiatAmount is passed from the parent top-up dialog, ensuring
/// the amount selection is shared between card and crypto flows.
class UnifiedCryptoFlow extends StatefulWidget {
  /// The amount in USD that the user wants to pay
  final double fiatAmount;

  /// Optional preselected token (skips token selection)
  final CryptoToken? preselectedToken;

  /// Current Turbo balance (in winc) for display on checkout
  final BigInt currentTurboBalance;

  /// Current balance storage estimate (e.g., "5.2 GB")
  final String currentBalanceStorage;

  /// Credits to receive (in winc) for calculating new balance
  final BigInt creditsToReceive;

  /// New balance storage estimate (e.g., "7.3 GB")
  final String newBalanceStorage;

  /// Callback when payment is successful (simple, no data)
  final VoidCallback? onSuccess;

  /// Callback when payment is successful with formatted data for success dialog
  /// Parameters: amountPaid, creditsReceived, storageEstimate, newBalanceCredits, newBalanceStorage
  final void Function({
    String? amountPaid,
    String? creditsReceived,
    String? storageEstimate,
    String? newBalanceCredits,
    String? newBalanceStorage,
  })? onSuccessWithData;

  /// Callback when user cancels or closes
  final VoidCallback? onCancel;

  /// Callback to go back to payment method selection
  final VoidCallback? onBack;

  UnifiedCryptoFlow({
    super.key,
    required this.fiatAmount,
    this.preselectedToken,
    BigInt? currentTurboBalance,
    this.currentBalanceStorage = '0 GB',
    BigInt? creditsToReceive,
    this.newBalanceStorage = '0 GB',
    this.onSuccess,
    this.onSuccessWithData,
    this.onCancel,
    this.onBack,
  })  : currentTurboBalance = currentTurboBalance ?? BigInt.zero,
        creditsToReceive = creditsToReceive ?? BigInt.zero;

  @override
  State<UnifiedCryptoFlow> createState() => _UnifiedCryptoFlowState();
}

class _UnifiedCryptoFlowState extends State<UnifiedCryptoFlow> {
  CryptoTopupBloc? _bloc;
  EthereumWalletService? _ethereumWalletService;
  SolanaWalletService? _solanaWalletService;
  bool _isInitialized = false;
  bool _successCallbackScheduled = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final auth = context.read<ArDriveAuth>();
    final configService = context.read<ConfigService>();

    // Determine environment for network config
    final environment =
        configService.config.useTurboUpload ? 'production' : 'development';
    final networkConfig = CryptoNetworkConfig.fromEnvironment(environment);

    // Create services
    final httpClient = ArDriveHTTP();
    final signerCache = WalletSignerCache();
    final priceService = CryptoPriceService(httpClient: httpClient);
    final gatewayUrl =
        configService.config.arweaveGatewayUrl ?? defaultGraphqlGateway;
    final cryptoPaymentService = CryptoPaymentService(
      networkConfig: networkConfig,
      httpClient: httpClient,
      signerCache: signerCache,
      priceService: priceService,
      arweaveGatewayUrl: gatewayUrl,
      arnsResolverUrl: gatewayUrl,
    );

    _ethereumWalletService = EthereumWalletService(
      networkConfig: networkConfig,
      getTokenPrice: priceService.getUsdPrice,
    );
    _solanaWalletService = SolanaWalletService(networkConfig: networkConfig);

    // Get SharedPreferences for transaction storage
    final prefs = await SharedPreferences.getInstance();
    final transactionStorage = CryptoTransactionStorage(prefs);

    // Create the BLoC with balance data for checkout display
    _bloc = CryptoTopupBloc(
      paymentService: cryptoPaymentService,
      ethereumWalletService: _ethereumWalletService!,
      solanaWalletService: _solanaWalletService!,
      signerCache: signerCache,
      transactionStorage: transactionStorage,
      arweaveWalletAddress: auth.currentUser.walletAddress,
      currentTurboBalance: widget.currentTurboBalance,
      currentBalanceStorage: widget.currentBalanceStorage,
      newBalanceStorage: widget.newBalanceStorage,
      // Pass the pre-fetched ARIO balance from ArDriveAuth for ARIO on AO tokens
      arioBalance: auth.currentUser.ioTokens,
    );

    // Initialize and set the amount
    _bloc!.add(const CryptoTopupStarted());
    // For crypto payments, fiatAmount is actually the token amount
    // Pass isUsd: false to use token-specific pricing (e.g., ARIO has no fees)
    _bloc!.add(CryptoTopupUpdateAmount(widget.fiatAmount, isUsd: false));

    // If a token was preselected, select it
    if (widget.preselectedToken != null) {
      _bloc!.add(CryptoTopupSelectToken(widget.preselectedToken!));
    }

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _bloc?.close();
    _ethereumWalletService?.dispose();
    _solanaWalletService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _bloc == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return BlocProvider.value(
      value: _bloc!,
      child: BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
        builder: (context, state) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _buildContent(context, state),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, CryptoTopupState state) {
    // Reset success callback flag when not in success state
    // This ensures the callback can be scheduled again for a new flow
    if (state is! CryptoTopupSuccess) {
      _successCallbackScheduled = false;
    }

    // When token is preselected, show streamlined wallet connection flow
    // (skips the InlineCryptoPayment which has redundant token selection)
    if (widget.preselectedToken != null) {
      // Wallet connection states - show wallet connection view
      if (state is CryptoTopupInitial ||
          state is CryptoTopupTokenSelection ||
          state is CryptoTopupWalletConnection ||
          state is CryptoTopupWalletNotInstalled ||
          state is CryptoTopupNetworkSwitch ||
          state is CryptoTopupAOConnectSignature) {
        return WalletConnectionView(
          key: const ValueKey('wallet_connection'),
          token: widget.preselectedToken!,
          fiatAmount: widget.fiatAmount,
          onBack: widget.onBack,
          onCancel: widget.onCancel,
        );
      }

      // Amount entry - automatically proceed to confirmation
      // (we already have the amount from the unified pay view)
      if (state is CryptoTopupAmountEntry) {
        // Trigger proceed to confirmation
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _bloc!.add(const CryptoTopupProceedToConfirmation());
        });
        return const Center(child: CircularProgressIndicator());
      }
    } else {
      // No preselected token - show full inline crypto payment flow
      // (this path is for when crypto flow is opened without token selection)
      if (state is CryptoTopupInitial ||
          state is CryptoTopupTokenSelection ||
          state is CryptoTopupWalletConnection ||
          state is CryptoTopupWalletNotInstalled ||
          state is CryptoTopupAmountEntry ||
          state is CryptoTopupAOConnectSignature) {
        return InlineCryptoPayment(
          key: const ValueKey('inline_crypto'),
          fiatAmount: widget.fiatAmount,
          onContinue: () {
            _bloc!.add(const CryptoTopupProceedToConfirmation());
          },
          onCancel: widget.onCancel,
          onBackToPaymentMethods: widget.onBack,
        );
      }
    }

    // Confirmation state
    if (state is CryptoTopupConfirmation) {
      return CryptoConfirmationView(
        key: const ValueKey('confirmation'),
        // When there's a preselected token, back should go to parent view
        // Otherwise, back goes to amount entry within the crypto flow
        onBack: widget.preselectedToken != null
            ? widget.onBack
            : () => _bloc!.add(const CryptoTopupGoBack()),
        onClose: widget.onCancel,
      );
    }

    // Processing state
    if (state is CryptoTopupProcessing) {
      return const CryptoProcessingView(
        key: ValueKey('processing'),
      );
    }

    // Success state
    if (state is CryptoTopupSuccess) {
      // If onSuccessWithData is provided, call it with formatted data
      // This allows the parent to show a separate success dialog (like credit card flow)
      if (widget.onSuccessWithData != null) {
        // Only schedule callback once per success to avoid multiple invocations
        if (!_successCallbackScheduled) {
          _successCallbackScheduled = true;

          // Format the data for the success dialog
          final amountPaid = _formatAmountPaid(state);
          final creditsReceived = _formatCredits(state.creditsAdded);
          final newBalanceCredits = state.newBalance != null
              ? _formatCredits(state.newBalance!)
              : null;

          // Schedule the callback after the build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onSuccessWithData!(
              amountPaid: amountPaid,
              creditsReceived: creditsReceived,
              storageEstimate: state.storageEstimate,
              newBalanceCredits: newBalanceCredits,
              newBalanceStorage: state.newBalanceStorage,
            );
          });
        }

        // Show a brief loading indicator while transitioning
        return const Center(child: CircularProgressIndicator());
      }

      // Fallback: render CryptoSuccessView inline (old behavior)
      return CryptoSuccessView(
        key: const ValueKey('success'),
        onDone: () {
          widget.onSuccess?.call();
        },
      );
    }

    // Error state
    if (state is CryptoTopupError) {
      return CryptoErrorView(
        key: const ValueKey('error'),
        onRetry:
            state.canRetry ? () => _bloc!.add(const CryptoTopupRetry()) : null,
        onClose: widget.onCancel,
      );
    }

    // Default loading
    return const Center(child: CircularProgressIndicator());
  }

  /// Format amount paid for display (e.g., "100 ARIO ($25.00)")
  String _formatAmountPaid(CryptoTopupSuccess state) {
    final tokenAmount = state.tokenAmountSpent;
    final symbol = state.token.symbol;
    final usdValue = state.usdValue;

    String tokenStr;
    if (tokenAmount >= 1000) {
      tokenStr = '${tokenAmount.toStringAsFixed(0)} $symbol';
    } else if (tokenAmount >= 1) {
      tokenStr = '${tokenAmount.toStringAsFixed(2)} $symbol';
    } else {
      tokenStr = '${tokenAmount.toStringAsFixed(4)} $symbol';
    }

    if (usdValue != null) {
      return '$tokenStr (\$${usdValue.toStringAsFixed(2)})';
    }
    return tokenStr;
  }

  /// Format credits for display (e.g., "0.25 Credits")
  /// Uses BigInt-safe formatting to preserve precision for large balances.
  String _formatCredits(BigInt credits) => formatCreditsFromWinc(credits);
}

/// A full-screen modal wrapper for the unified crypto flow.
///
/// Use this when you want to show the crypto flow as a modal dialog
/// rather than embedded in the main top-up view.
class UnifiedCryptoModal extends StatelessWidget {
  final double fiatAmount;
  final CryptoToken? preselectedToken;
  final VoidCallback? onClose;
  final VoidCallback? onBackToPaymentMethods;

  const UnifiedCryptoModal({
    super.key,
    required this.fiatAmount,
    this.preselectedToken,
    this.onClose,
    this.onBackToPaymentMethods,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveModal(
      constraints: const BoxConstraints(
        maxWidth: 480,
        maxHeight: 640,
      ),
      content: SizedBox(
        width: 480,
        height: 560,
        child: UnifiedCryptoFlow(
          fiatAmount: fiatAmount,
          preselectedToken: preselectedToken,
          onSuccess: () {
            Navigator.of(context).pop();
            onClose?.call();
          },
          onCancel: () {
            Navigator.of(context).pop();
            onClose?.call();
          },
          onBack: () {
            Navigator.of(context).pop();
            // If we have a callback to go back to payment methods, call it
            if (onBackToPaymentMethods != null) {
              onBackToPaymentMethods!();
            } else {
              onClose?.call();
            }
          },
        ),
      ),
    );
  }
}

/// Shows the unified crypto modal
Future<void> showUnifiedCryptoModal(
  BuildContext context, {
  required double fiatAmount,
  CryptoToken? preselectedToken,
  VoidCallback? onClose,
  VoidCallback? onBackToPaymentMethods,
}) async {
  final themeColors = ArDriveTheme.of(context).themeData.colors;

  await showAnimatedDialog(
    context,
    barrierDismissible: false,
    barrierColor: themeColors.shadow.withOpacity(0.9),
    content: MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: context.read<ArDriveAuth>()),
        RepositoryProvider.value(value: context.read<ConfigService>()),
      ],
      child: UnifiedCryptoModal(
        fiatAmount: fiatAmount,
        preselectedToken: preselectedToken,
        onClose: onClose,
        onBackToPaymentMethods: onBackToPaymentMethods,
      ),
    ),
  );
}

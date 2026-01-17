import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/services/crypto_payment_service.dart';
import 'package:ardrive/turbo/services/crypto_transaction_storage.dart';
import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_confirmation_view.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_processing_view.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_result_view.dart';
import 'package:ardrive/turbo/topup/views/unified/inline_crypto_payment.dart';
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

  /// Callback when payment is successful
  final VoidCallback? onSuccess;

  /// Callback when user cancels or closes
  final VoidCallback? onCancel;

  /// Callback to go back to payment method selection
  final VoidCallback? onBack;

  const UnifiedCryptoFlow({
    super.key,
    required this.fiatAmount,
    this.onSuccess,
    this.onCancel,
    this.onBack,
  });

  @override
  State<UnifiedCryptoFlow> createState() => _UnifiedCryptoFlowState();
}

class _UnifiedCryptoFlowState extends State<UnifiedCryptoFlow> {
  CryptoTopupBloc? _bloc;
  EthereumWalletService? _ethereumWalletService;
  SolanaWalletService? _solanaWalletService;
  bool _isInitialized = false;

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
    final cryptoPaymentService = CryptoPaymentService(
      networkConfig: networkConfig,
      httpClient: httpClient,
      signerCache: signerCache,
    );

    _ethereumWalletService = EthereumWalletService(networkConfig: networkConfig);
    _solanaWalletService = SolanaWalletService(networkConfig: networkConfig);

    // Get SharedPreferences for transaction storage
    final prefs = await SharedPreferences.getInstance();
    final transactionStorage = CryptoTransactionStorage(prefs);

    // Create the BLoC
    _bloc = CryptoTopupBloc(
      paymentService: cryptoPaymentService,
      ethereumWalletService: _ethereumWalletService!,
      solanaWalletService: _solanaWalletService!,
      signerCache: signerCache,
      transactionStorage: transactionStorage,
      arweaveWalletAddress: auth.currentUser.walletAddress,
    );

    // Initialize and set the fiat amount
    _bloc!.add(const CryptoTopupStarted());
    _bloc!.add(CryptoTopupUpdateAmount(widget.fiatAmount));

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
    // Initial/Token selection/Wallet connection/Amount entry states
    // These all show the inline crypto payment view
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

    // Confirmation state
    if (state is CryptoTopupConfirmation) {
      return CryptoConfirmationView(
        key: const ValueKey('confirmation'),
        onBack: () => _bloc!.add(const CryptoTopupGoBack()),
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
        onRetry: state.canRetry
            ? () => _bloc!.add(const CryptoTopupRetry())
            : null,
        onClose: widget.onCancel,
      );
    }

    // Default loading
    return const Center(child: CircularProgressIndicator());
  }
}

/// A full-screen modal wrapper for the unified crypto flow.
///
/// Use this when you want to show the crypto flow as a modal dialog
/// rather than embedded in the main top-up view.
class UnifiedCryptoModal extends StatelessWidget {
  final double fiatAmount;
  final VoidCallback? onClose;

  const UnifiedCryptoModal({
    super.key,
    required this.fiatAmount,
    this.onClose,
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
          onSuccess: () {
            Navigator.of(context).pop();
            onClose?.call();
          },
          onCancel: () {
            Navigator.of(context).pop();
            onClose?.call();
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
  VoidCallback? onClose,
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
        onClose: onClose,
      ),
    ),
  );
}

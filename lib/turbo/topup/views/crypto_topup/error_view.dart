import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/components/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Error view - shown when payment fails.
class ErrorView extends StatelessWidget {
  final VoidCallback? onCancel;

  const ErrorView({
    super.key,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      buildWhen: (previous, current) => current is CryptoTopupError,
      builder: (context, state) {
        if (state is! CryptoTopupError) {
          return const SizedBox.shrink();
        }

        return _ErrorContent(
          state: state,
          onCancel: onCancel,
        );
      },
    );
  }
}

class _ErrorContent extends StatelessWidget {
  final CryptoTopupError state;
  final VoidCallback? onCancel;

  const _ErrorContent({
    required this.state,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<CryptoTopupBloc>();

    return TransactionErrorView(
      errorMessage: _getErrorMessage(state),
      txId: state.txId,
      token: state.token,
      canRetry: state.canRetry,
      onRetry: state.canRetry ? () => bloc.add(const CryptoTopupRetry()) : null,
      onCancel: onCancel ?? () => bloc.add(const CryptoTopupClose()),
    );
  }

  String _getErrorMessage(CryptoTopupError state) {
    switch (state.errorType) {
      case CryptoTopupErrorType.network:
        return 'Network error. Please check your connection and try again.';
      case CryptoTopupErrorType.insufficientFunds:
        return 'Insufficient funds in your wallet to complete this transaction.';
      case CryptoTopupErrorType.insufficientGas:
        return 'Insufficient funds for gas fees. Please add more ETH to your wallet.';
      case CryptoTopupErrorType.transactionFailed:
        return state.message.isNotEmpty
            ? state.message
            : 'Transaction failed. Please try again.';
      case CryptoTopupErrorType.transactionRejected:
        return 'Transaction was rejected. Please try again if this was unintentional.';
      case CryptoTopupErrorType.quoteExpired:
        return 'Your quote has expired. Please get a new quote and try again.';
      case CryptoTopupErrorType.promoCodeInvalid:
        return 'The promo code is invalid or has expired.';
      case CryptoTopupErrorType.sessionExpired:
        return 'Your session has expired. Please start a new payment.';
      case CryptoTopupErrorType.unknown:
        return state.message.isNotEmpty
            ? state.message
            : 'An unexpected error occurred. Please try again.';
    }
  }
}

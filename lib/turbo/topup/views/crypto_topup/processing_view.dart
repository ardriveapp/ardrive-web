import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/components/components.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Processing view - shown while transaction is being processed.
class ProcessingView extends StatelessWidget {
  const ProcessingView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      buildWhen: (previous, current) => current is CryptoTopupProcessing,
      builder: (context, state) {
        if (state is! CryptoTopupProcessing) {
          return const SizedBox.shrink();
        }

        return _ProcessingContent(state: state);
      },
    );
  }
}

class _ProcessingContent extends StatelessWidget {
  final CryptoTopupProcessing state;

  const _ProcessingContent({required this.state});

  @override
  Widget build(BuildContext context) {
    final status = state.isSubmitting
        ? TransactionDisplayStatus.submitting
        : state.txId != null
            ? TransactionDisplayStatus.confirming
            : TransactionDisplayStatus.pending;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          TransactionStatusDisplay(
            status: status,
            txId: state.txId,
            token: state.token,
            message: _getMessage(state),
          ),
          const Spacer(),
          _ProcessingInfo(state: state),
        ],
      ),
    );
  }

  String? _getMessage(CryptoTopupProcessing state) {
    if (state.isSubmitting) {
      return 'Please confirm the transaction in your wallet.';
    }
    if (state.txId != null) {
      return 'Your transaction is being confirmed on the blockchain.';
    }
    return 'Please wait while we process your payment.';
  }
}

class _ProcessingInfo extends StatelessWidget {
  final CryptoTopupProcessing state;

  const _ProcessingInfo({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: colorTokens.textMid,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Do not close this window',
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textHigh,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your transaction is being processed. Closing this window may cause the transaction to fail.',
            style: typography.paragraphSmall(
              color: colorTokens.textMid,
            ),
          ),
        ],
      ),
    );
  }
}

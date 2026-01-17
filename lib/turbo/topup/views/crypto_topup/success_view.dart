import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/components/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Success view - shown after successful payment.
class SuccessView extends StatelessWidget {
  final VoidCallback? onDone;

  const SuccessView({
    super.key,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      buildWhen: (previous, current) => current is CryptoTopupSuccess,
      builder: (context, state) {
        if (state is! CryptoTopupSuccess) {
          return const SizedBox.shrink();
        }

        return _SuccessContent(
          state: state,
          onDone: onDone,
        );
      },
    );
  }
}

class _SuccessContent extends StatelessWidget {
  final CryptoTopupSuccess state;
  final VoidCallback? onDone;

  const _SuccessContent({
    required this.state,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<CryptoTopupBloc>();

    // Format credits for display
    final creditsDisplay = _formatCredits(state.creditsAdded);
    final newBalanceDisplay =
        state.newBalance != null ? _formatCredits(state.newBalance!) : null;

    return TransactionSuccessView(
      txId: state.txId,
      creditsAdded: creditsDisplay,
      newBalance: newBalanceDisplay,
      token: state.token,
      onDone: onDone ?? () => bloc.add(const CryptoTopupClose()),
    );
  }

  String _formatCredits(BigInt credits) {
    // Convert from winstons to readable credits format
    // 1 credit = 10^12 winstons
    final creditsDouble = credits / BigInt.from(10).pow(12);
    return '${creditsDouble.toStringAsFixed(4)} Credits';
  }
}

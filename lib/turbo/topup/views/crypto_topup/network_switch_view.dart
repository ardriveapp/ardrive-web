import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/components/components.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Network switch view - shown when user needs to switch networks manually.
class NetworkSwitchView extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const NetworkSwitchView({
    super.key,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      buildWhen: (previous, current) => current is CryptoTopupNetworkSwitch,
      builder: (context, state) {
        if (state is! CryptoTopupNetworkSwitch) {
          return const SizedBox.shrink();
        }

        return _NetworkSwitchContent(
          state: state,
          onBack: onBack,
          onClose: onClose,
        );
      },
    );
  }
}

class _NetworkSwitchContent extends StatelessWidget {
  final CryptoTopupNetworkSwitch state;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const _NetworkSwitchContent({
    required this.state,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final bloc = context.read<CryptoTopupBloc>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Row(
            children: [
              if (onBack != null)
                GestureDetector(
                  onTap: onBack,
                  child: Icon(
                    Icons.arrow_back,
                    color: colorTokens.textMid,
                    size: 24,
                  ),
                ),
              if (onBack != null) const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Switch Network',
                  style: typography.heading4(
                    fontWeight: ArFontWeight.bold,
                    color: colorTokens.textHigh,
                  ),
                ),
              ),
              if (onClose != null)
                GestureDetector(
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    color: colorTokens.textMid,
                    size: 24,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Network info
          _NetworkComparisonCard(
            currentChainId: state.currentChainId,
            requiredChainId: state.requiredChainId,
          ),
          const SizedBox(height: 24),

          // Error message
          if (state.error != null) ...[
            _ErrorMessage(message: state.error!),
            const SizedBox(height: 16),
          ],

          // Manual instructions toggle
          if (state.showManualInstructions) ...[
            ManualNetworkSwitchInstructions(token: state.token),
            const SizedBox(height: 24),
          ],

          // Action buttons
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              text: state.isSwitching
                  ? 'Switching...'
                  : state.isAdding
                      ? 'Adding Network...'
                      : 'Switch Network',
              onPressed: state.isSwitching || state.isAdding
                  ? null
                  : () => bloc.add(CryptoTopupSwitchNetwork(state.requiredChainId)),
              isDisabled: state.isSwitching || state.isAdding,
            ),
          ),
          const SizedBox(height: 12),

          // Show manual instructions button
          if (!state.showManualInstructions)
            Center(
              child: GestureDetector(
                onTap: () => bloc.add(const CryptoTopupShowManualNetworkSwitch()),
                child: Text(
                  'Show manual instructions',
                  style: typography.paragraphSmall(
                    color: colorTokens.textMid,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NetworkComparisonCard extends StatelessWidget {
  final int currentChainId;
  final int requiredChainId;

  const _NetworkComparisonCard({
    required this.currentChainId,
    required this.requiredChainId,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Column(
        children: [
          // Current network
          _NetworkRow(
            label: 'Current Network',
            chainId: currentChainId,
            isActive: true,
          ),
          const SizedBox(height: 16),
          // Arrow
          Icon(
            Icons.arrow_downward,
            color: colorTokens.textMid,
            size: 24,
          ),
          const SizedBox(height: 16),
          // Required network
          _NetworkRow(
            label: 'Required Network',
            chainId: requiredChainId,
            isActive: false,
          ),
        ],
      ),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  final String label;
  final int chainId;
  final bool isActive;

  const _NetworkRow({
    required this.label,
    required this.chainId,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      children: [
        // Network indicator
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isActive
                ? colorTokens.containerL2
                : colorTokens.containerL3,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: getNetworkColor(chainId),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Network info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: typography.paragraphSmall(
                  color: colorTokens.textMid,
                ),
              ),
              Text(
                getNetworkName(chainId),
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textHigh,
                ),
              ),
            ],
          ),
        ),
        // Status
        if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorTokens.containerL2,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Connected',
              style: typography.paragraphSmall(
                color: colorTokens.textMid,
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;

  const _ErrorMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: colorTokens.textLow,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: typography.paragraphSmall(
                color: colorTokens.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

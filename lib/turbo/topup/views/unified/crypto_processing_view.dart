import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Processing view shown while crypto payment is being processed.
class CryptoProcessingView extends StatelessWidget {
  const CryptoProcessingView({super.key});

  @override
  Widget build(BuildContext context) {
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        String message = 'Processing your payment...';
        String? submessage;

        if (state is CryptoTopupProcessing) {
          if (state.isSubmitting) {
            message = 'Please approve in your wallet';
            submessage =
                'Check your wallet extension for the signature request';
          } else if (state.txId != null) {
            message = 'Confirming transaction...';
            submessage = 'Waiting for network confirmation';
          } else {
            message = 'Submitting transaction...';
            submessage = 'This may take a moment';
          }
        }

        return Column(
          children: [
            // Red top line (ArDrive modal pattern)
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: colorTokens.containerRed,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
            ),
            // Main content
            Flexible(
              child: Container(
                color: colors.themeBgCanvas,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Animated loading indicator
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: colorTokens.containerRed,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Main message
                        Text(
                          message,
                          style: typography.heading5(
                            fontWeight: ArFontWeight.semiBold,
                            color: colors.themeFgDefault,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        // Sub message
                        if (submessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            submessage,
                            style: typography.paragraphNormal(
                              color: colors.themeFgMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        const SizedBox(height: 48),

                        // Don't close warning
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.themeBgSubtle,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: colors.themeFgMuted,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Please don't close this window",
                                style: typography.paragraphSmall(
                                  color: colors.themeFgMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

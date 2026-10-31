import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Processing view shown while crypto payment is being processed.
class CryptoProcessingView extends StatelessWidget {
  const CryptoProcessingView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        String message = 'Processing your payment...';
        String? submessage;

        if (state is CryptoTopupProcessing) {
          if (state.isSubmitting) {
            // One SDK call sends the payment and waits for the network, so
            // this covers both: the wallet's prompt and the confirmation.
            message = 'Approve the payment in your wallet';
            submessage = 'Once you approve it, it can take a minute to confirm';
          } else if (state.txId != null) {
            message = 'Confirming transaction...';
            submessage = 'Waiting for network confirmation';
          } else {
            message = 'Submitting transaction...';
            submessage = 'This may take a moment';
          }
        }

        // No close button: the payment is under way.
        return TurboTopupScaffold(
          // A heading for the dialog, which screen readers announce on open.
          title: 'Payment in progress',
          canClose: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ArDriveSpinner(
                  size: ArDriveSpinnerSize.large,
                  semanticsLabel: message,
                ),
                const SizedBox(height: 32),

                // The step changes in place (approve, submit, confirm), so
                // it is a live region: a screen reader hears each one.
                Semantics(
                  liveRegion: true,
                  child: Column(
                    children: [
                      // Main message
                      Text(
                        message,
                        style: typography.heading5(
                          fontWeight: ArFontWeight.semiBold,
                          color: colors.textHigh,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // Sub message
                      if (submessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          submessage,
                          style: typography.paragraphNormal(
                            color: colors.textMid,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Don't close warning
                const ArDriveNotice(
                  type: ArDriveNoticeType.info,
                  message: "Please don't close this window",
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

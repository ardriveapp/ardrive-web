import 'package:ardrive/authentication/components/login_card.dart';
import 'package:ardrive/sync/presentation/sync_loading_indicator.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The sign-in panel while a new account's key is made on this device: up to
/// a minute, so it says what is happening and why it is safe.
class CreatingAccountView extends StatelessWidget {
  const CreatingAccountView({super.key, this.noWalletFound = false});

  /// Sign up found no wallet to offer and came straight here: say so, for
  /// someone who expected to use theirs.
  final bool noWalletFound;

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    return SizedBox(
      width: 381,
      child: LoginCard(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The plate stack: ArDrive's own "working" mark.
            Semantics(
              label: s.creatingAccountTitle,
              child: const Center(child: SyncLoadingIndicator(size: 96)),
            ),
            const SizedBox(height: 16),
            Text(
              s.creatingAccountTitle,
              textAlign: TextAlign.center,
              style: type.heading2(
                color: colors.textHigh,
                fontWeight: ArFontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.creatingAccountBody,
              textAlign: TextAlign.center,
              style: type.paragraphNormal(color: colors.textMid),
            ),
            if (noWalletFound) ...[
              const SizedBox(height: 8),
              Text(
                s.creatingAccountNoWallet,
                key: const Key('creatingAccountNoWallet'),
                textAlign: TextAlign.center,
                style: type.paragraphNormal(color: colors.textMid),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              s.creatingAccountKeepOpen,
              textAlign: TextAlign.center,
              style: type.paragraphSmall(color: colors.textLow),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// On the sign-in screen after ArDrive signed out because Wander moved to
/// another account; see `ProfileCubit.signOutForOtherWallet`.
class WalletSwitchDialog extends StatelessWidget {
  const WalletSwitchDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    return ArDriveStandardModalNew(
      title: l10n.wanderAccountChangedTitle,
      description: l10n.wanderAccountChangedDescription,
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(),
          title: l10n.okEmphasized,
        ),
      ],
    );
  }
}

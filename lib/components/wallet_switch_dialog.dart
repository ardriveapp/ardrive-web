// ignore_for_file: use_build_context_synchronously

import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class WalletSwitchDialog extends StatelessWidget {
  final bool fromAuthPage;

  const WalletSwitchDialog({super.key, this.fromAuthPage = false});
  @override
  Widget build(BuildContext context) => ArDriveStandardModalNew(
        title: appLocalizationsOf(context).walletSwitch,
        description: appLocalizationsOf(context).walletChangeDetected,
      );
}

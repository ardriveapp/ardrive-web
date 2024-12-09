// ignore_for_file: use_build_context_synchronously

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WalletSwitchDialog extends StatelessWidget {
  final bool fromAuthPage;

  const WalletSwitchDialog({super.key, this.fromAuthPage = false});
  @override
  Widget build(BuildContext context) => ArDriveStandardModalNew(
        title: appLocalizationsOf(context).walletSwitch,
        description: appLocalizationsOf(context).walletChangeDetected,
        actions: [
          ModalAction(
            action: () async {
              await context.read<ArDriveAuth>().logout();
              await context.read<ProfileCubit>().logoutProfile();

              Navigator.pop(context);

              if (fromAuthPage) {
                triggerHTMLPageReload();
                context.read<ProfileAddCubit>().promptForWallet();
              }
            },
            title: appLocalizationsOf(context).logOut,
          )
        ],
      );
}

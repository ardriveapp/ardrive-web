// ignore_for_file: use_build_context_synchronously

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/app_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// TODO: Add the new modal PE-4381
class WalletSwitchDialog extends StatelessWidget {
  final bool fromAuthPage;

  const WalletSwitchDialog({Key? key, this.fromAuthPage = false})
      : super(key: key);
  @override
  Widget build(BuildContext context) => AppDialog(
        dismissable: false,
        title: appLocalizationsOf(context).walletSwitch,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [Text(appLocalizationsOf(context).walletChangeDetected)],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await context.read<ArDriveAuth>().logout();
              await context.read<ProfileCubit>().logoutProfile();

              Navigator.pop(context);

              if (fromAuthPage) {
                triggerHTMLPageReload();
                context.read<ProfileAddCubit>().promptForWallet();
              }
            },
            child: Text(appLocalizationsOf(context).logOut),
          )
        ],
      );
}

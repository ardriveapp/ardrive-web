import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/app_dialog.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../utils/app_localizations_wrapper.dart';

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
            onPressed: () {
              Navigator.pop(context);
              context.read<ProfileCubit>().logoutProfile();
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

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/app_dialog.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WalletSwitchDialog extends StatelessWidget {
  final bool fromAuthPage;

  const WalletSwitchDialog({Key? key, this.fromAuthPage = false})
      : super(key: key);
  @override
  Widget build(BuildContext context) => AppDialog(
        dismissable: false,
        title: 'Wallet Switch',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Wallet change detected. Please log out and log in again')
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (context.read<ActivityCubit>().state is ActivityInProgress) {
                Navigator.pop(context);
              }
              Navigator.pop(context);
              context.read<ProfileCubit>().logoutProfile();
              if (fromAuthPage) {
                triggerHTMLPageReload();
                context.read<ProfileAddCubit>().promptForWallet();
              }
            },
            child: Text('Logout'),
          )
        ],
      );
}

import 'dart:html';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WalletSwitchDialog extends StatelessWidget {
  final bool fromAuthPage;

  const WalletSwitchDialog({Key key, this.fromAuthPage}) : super(key: key);
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
            child: Text('Logout'),
            onPressed: () {
              Navigator.pop(context);
              context.read<ProfileCubit>().logoutProfile();
              if (fromAuthPage ?? false) {
                window.location.reload();
                context.read<ProfileAddCubit>().promptForWallet();
              }
            },
          )
        ],
      );
}

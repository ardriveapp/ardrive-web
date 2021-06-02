import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/app_dialog.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/link.dart';

class WalletSwitchDialog extends StatelessWidget {
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
          Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kMediumDialogWidth),
                child: BlocBuilder<ProfileCubit, ProfileState>(
                  builder: (context, state) => state is ProfileLoggedIn
                      ? TextButton(
                          child: Text('Logout'),
                          onPressed: () {
                            Navigator.pop(context);
                            context.read<ProfileCubit>().logoutProfile();
                          },
                        )
                      : ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('You\'re not logged in'),
                          subtitle: Text(
                              'Log in to experience all of ArDrive\'s features!'),
                          trailing: Link(
                            uri: Uri(path: '/sign-in'),
                            builder: (context, onPressed) => IconButton(
                              icon: const Icon(Icons.login),
                              tooltip: 'Login',
                              onPressed: onPressed,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      );
}

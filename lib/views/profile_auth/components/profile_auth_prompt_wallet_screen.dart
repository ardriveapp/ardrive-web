import 'package:ardrive/blocs/blocs.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/link.dart';

import 'profile_auth_shell.dart';

class ProfileAuthPromptWalletScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          'assets/images/illustrations/illus_profile_welcome.png',
          fit: BoxFit.scaleDown,
        ),
        content: FractionallySizedBox(
          widthFactor: 0.5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WELCOME TO',
                style: Theme.of(context).textTheme.headline5,
              ),
              Container(height: 32),
              Text(
                'Your private and secure, decentralized, pay-as-you-go, censorship-resistant and permanent hard drive.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headline6,
              ),
              Container(height: 32),
              ElevatedButton(
                child: Text('SELECT WALLET'),
                onPressed: () => _pickWallet(context),
              ),
              Container(height: 16),
              Link(
                uri: Uri.parse('https://tokens.arweave.org'),
                target: LinkTarget.blank,
                builder: (context, followLink) => TextButton(
                  onPressed: followLink,
                  child: Text(
                    'Don\'t have a wallet? Get one here!',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  void _pickWallet(BuildContext context) async {
    try {
      final chooseResult = await FilePickerCross.importFromStorage();
      await context.bloc<ProfileAddCubit>().pickWallet(chooseResult.toString());
    } catch (err) {
      if (err is! FileSelectionCanceledError) {
        rethrow;
      }
    }
  }
}

import 'package:ardrive/blocs/blocs.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'profile_auth_shell.dart';

class ProfileAuthPromptWalletScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          'assets/illustrations/illus_profile_welcome.png',
          fit: BoxFit.fitWidth,
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
            ],
          ),
        ),
      );

  void _pickWallet(BuildContext context) async {
    var chooseResult;
    try {
      chooseResult = await FilePickerCross.pick();
      // ignore: empty_catches
    } catch (err) {}

    if (chooseResult != null && chooseResult.type != null) {
      await context.bloc<ProfileAddCubit>().pickWallet(chooseResult.toString());
    }
  }
}

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'profile_auth_shell.dart';

class ProfileAuthPromptWalletScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          R.images.profile.profileWelcome,
          fit: BoxFit.contain,
        ),
        contentWidthFactor: 0.5,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WELCOME TO',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headline5,
            ),
            const SizedBox(height: 32),
            Text(
              'Your private and secure, decentralized, pay-as-you-go, censorship-resistant and permanent hard drive.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headline6,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _pickWallet(context),
              child: Text(AppLocalizations.of(context)!.selectWalletEmphasized),
            ),
            if (context.read<ProfileAddCubit>().isArconnectInstalled()) ...[
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => _pickWalletArconnect(context),
                child:
                    Text(AppLocalizations.of(context)!.useArconnectEmphasized),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => launch('https://tokens.arweave.org'),
              child: Text(
                AppLocalizations.of(context)!.getAWallet,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );

  void _pickWallet(BuildContext context) async {
    final walletFile = await file_selector.openFile(acceptedTypeGroups: [
      file_selector.XTypeGroup(label: 'wallet keys', extensions: ['json'])
    ]);

    if (walletFile == null) {
      return;
    }

    await context
        .read<ProfileAddCubit>()
        .pickWallet(await walletFile.readAsString());
  }

  void _pickWalletArconnect(BuildContext context) async {
    await context.read<ProfileAddCubit>().pickWalletFromArconnect();
  }
}

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
              // TODO replace at PE-1125
              appLocalizationsOf(context).welcomeTo_main,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headline5,
            ),
            const SizedBox(height: 32),
            Text(
              // TODO replace at PE-1125
              appLocalizationsOf(context).welcomeTo_description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headline6,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _pickWallet(context),
              child: Text(appLocalizationsOf(context).selectWalletEmphasized),
            ),
            if (context.read<ProfileAddCubit>().isArconnectInstalled()) ...[
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => _pickWalletArconnect(context),
                child: Text(appLocalizationsOf(context).useArconnectEmphasized),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => launch('https://tokens.arweave.org'),
              child: Text(
                appLocalizationsOf(context).getAWallet,
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

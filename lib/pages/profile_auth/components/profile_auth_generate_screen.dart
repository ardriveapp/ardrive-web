import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/download_wallet_dialog.dart';
import 'package:ardrive/components/generate_seedphrase_dialog.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'profile_auth_shell.dart';

class ProfileAuthGenerateScreen extends StatelessWidget {
  const ProfileAuthGenerateScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          Resources.images.profile.profileWelcome,
          fit: BoxFit.contain,
        ),
        contentWidthFactor: 0.5,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Generate Wallet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headline5,
            ),
            const SizedBox(height: 32),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Download Keyfile'),
                  onTap: () => showDownloadWalletDialog(
                    context: context,
                    onWalletGenerated: (wallet) {
                      context
                          .read<ProfileAddCubit>()
                          .generateWalletSaveAndPick(wallet);
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(height: 32),
                ListTile(
                  leading: const Icon(Icons.note_alt_outlined),
                  title: const Text('Generate Seedphrase'),
                  onTap: () => showGenerateSeedphraseDialog(
                    context: context,
                    onGenerateMnemonic: ((seedphrase) {
                      context
                          .read<ProfileAddCubit>()
                          .pickWalletFromMnemonic(seedphrase);
                      Navigator.pop(context);
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: () {
                context.read<ProfileCubit>().logoutProfile();
                triggerHTMLPageReload();
                context.read<ProfileAddCubit>().promptForWallet();
              },
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
}

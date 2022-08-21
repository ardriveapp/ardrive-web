import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/services/analytics/ardrive_analytics.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'profile_auth_shell.dart';

class ProfileAuthPromptWalletScreen extends StatelessWidget {
  const ProfileAuthPromptWalletScreen({Key? key}) : super(key: key);

  // TODO; An object-based, maybe hierarchical way to structure these constants
  final _screenName = "pickWallet";
  final _pickedWalletEventName = "pickedWallet";
  final _walletTypeDimension = "walletType";

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
            ...splitTranslationsWithMultipleStyles<Widget>(
              originalText: appLocalizationsOf(context).welcomeTo_body,
              defaultMapper: (text) => Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headline6,
              ),
              parts: {
                appLocalizationsOf(context).welcomeTo_main: (text) => Text(
                      text,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headline5,
                    ),
              },
              separator: const SizedBox(height: 32),
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
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://tokens.arweave.org',
                ),
              ),
              child: Text(
                appLocalizationsOf(context).getAWallet,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );

  void _pickWallet(BuildContext context) async {
    final ardriveIO = ArDriveIO();

    context.read<ArDriveAnalytics>().trackScreenEvent(
      screenName: _screenName,
      eventName: _pickedWalletEventName,
      dimensions: {_walletTypeDimension: "json"},
    );

    final walletFile = await ardriveIO.pickFile(allowedExtensions: ['json']);

    await context
        .read<ProfileAddCubit>()
        .pickWallet(await walletFile.readAsString());
  }

  void _pickWalletArconnect(BuildContext context) async {
    context.read<ArDriveAnalytics>().trackScreenEvent(
      screenName: _screenName,
      eventName: _pickedWalletEventName,
      dimensions: {_walletTypeDimension: "arconnect"},
    );
    await context.read<ProfileAddCubit>().pickWalletFromArconnect();
  }
}

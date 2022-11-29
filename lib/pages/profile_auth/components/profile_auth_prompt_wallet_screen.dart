import 'dart:convert';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/file_picker_modal.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'profile_auth_shell.dart';

class ProfileAuthPromptWalletScreen extends StatelessWidget {
  const ProfileAuthPromptWalletScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          Resources.images.profile.profileWelcome,
          fit: BoxFit.contain,
        ),
        contentWidthFactor: 0.5,
        content: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Welcome to ArDrive',
              textAlign: TextAlign.center,
              style: ArDriveTypography.headline.headline3Bold(),
            ),
            const SizedBox(height: 32),
            ArDriveDropAreaSingleInput(
              width: 552,
              height: 204,
              dragAndDropDescription: 'Drag & Drop your Keyfile',
              dragAndDropButtonTitle: 'Browse Json',
              onDragDone: (file) => pickWallet(file, context),
              buttonCallback: (file) => pickWallet(file, context),
            ),
            if (context.read<ProfileAddCubit>().isArconnectInstalled()) ...[
              const SizedBox(height: 32),
              ArDriveButton(
                onPressed: () => _pickWalletArconnect(context),
                text: appLocalizationsOf(context).useArconnectEmphasized,
              ),
            ],
            const SizedBox(height: 16),
            ArDriveTextButton(
              onPressed: () => openUrl(url: 'https://tokens.arweave.org'),
              text: appLocalizationsOf(context).getAWallet,
            ),
            // const Spacer(),
          ],
        ),
      );

  void _pickWallet(BuildContext context) async {
    final ardriveIO = ArDriveIO();

    final hasStoragePermission =
        await verifyStoragePermissionAndShowModalWhenDenied(
      context,
    );

    if (hasStoragePermission) {
      final walletFile = await ardriveIO.pickFile(
        allowedExtensions: null,
        fileSource: FileSource.fileSystem,
      );

      int walletSize = await walletFile.length;
      int maxWalletSizeInBits = 10000;

      if (walletSize > maxWalletSizeInBits) {
        // ignore: use_build_context_synchronously
        _showInvalidWalletFileDialog(context);
        return;
      }

      Wallet wallet;

      try {
        wallet = Wallet.fromJwk(json.decode(await walletFile.readAsString()));
      } catch (e) {
        // ignore: use_build_context_synchronously
        _showInvalidWalletFileDialog(context);
        return;
      }

      // ignore: use_build_context_synchronously
      await context.read<ProfileAddCubit>().pickWallet(wallet);
    }
  }

  Future<void> pickWallet(IOFile walletFile, BuildContext context) async {
    int walletSize = await walletFile.length;
    int maxWalletSizeInBits = 10000;

    if (walletSize > maxWalletSizeInBits) {
      // ignore: use_build_context_synchronously
      _showInvalidWalletFileDialog(context);
      return;
    }

    Wallet wallet;

    try {
      wallet = Wallet.fromJwk(json.decode(await walletFile.readAsString()));
    } catch (e) {
      // ignore: use_build_context_synchronously
      _showInvalidWalletFileDialog(context);
      return;
    }

    // ignore: use_build_context_synchronously
    await context.read<ProfileAddCubit>().pickWallet(wallet);
  }

  void _pickWalletArconnect(BuildContext context) async {
    await context.read<ProfileAddCubit>().pickWalletFromArconnect();
  }

  void _showInvalidWalletFileDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) {
          return AppDialog(
            title: appLocalizationsOf(context).invalidWalletFile,
            content: Text(
              appLocalizationsOf(context).invalidWalletFileDescription,
            ),
          );
        });
  }
}

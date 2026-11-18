import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/help_info_modals.dart';
import 'package:ardrive/user/download_wallet/bloc/download_wallet_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Asks for the password, then downloads the wallet as a keyfile. [ioUtils]
/// saves the file; a test passes its own.
void showDownloadWalletModal(BuildContext context, {ArDriveIOUtils? ioUtils}) {
  showArDriveDialog(
    context,
    content: BlocProvider<DownloadWalletBloc>(
      create: (_) => DownloadWalletBloc(
        ardriveAuth: context.read<ArDriveAuth>(),
        ardriveIOUtils: ioUtils ?? ArDriveIOUtils(),
      ),
      child: DownloadWalletModal(),
    ),
  );
}

class DownloadWalletModal extends StatelessWidget {
  DownloadWalletModal({super.key});

  final _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DownloadWalletBloc, DownloadWalletState>(
      listener: (context, state) {
        if (state is DownloadWalletSuccess) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        return ArDriveStandardModalNew(
          title: appLocalizationsOf(context).downloadWalletKeyfile,
          content: Column(
            children: [
              ArDriveTextFieldNew(
                autofocus: true,
                controller: _passwordController,
                label: appLocalizationsOf(context).password,
                errorMessage: state is DownloadWalletWrongPassword
                    ? appLocalizationsOf(context).validationPasswordIncorrect
                    : null,
                isEnabled: state is! DownloadWalletLoading,
                obscureText: true,
                showObfuscationToggle: true,
                onFieldSubmitted: (_) {
                  context
                      .read<DownloadWalletBloc>()
                      .add(DownloadWallet(_passwordController.text));
                },
              ),
              if (state is DownloadWalletFailure) ...[
                const SizedBox(height: ArDriveSpacing.md),
                ArDriveNotice(
                  type: ArDriveNoticeType.error,
                  message: appLocalizationsOf(context)
                      .anErrorOccuredWhileDownloadingYourKeyfile,
                ),
              ],
              const SizedBox(height: ArDriveSpacing.md),
              ArDriveLink(
                text: appLocalizationsOf(context).whatIsAKeyFile,
                onTap: () => showKeyfileInfoModal(context: context),
              )
            ],
          ),
          actions: [
            ModalAction.close(
              title: appLocalizationsOf(context).cancel,
              isEnable: state is! DownloadWalletLoading,
              action: () {
                Navigator.of(context).pop();
              },
            ),
            ModalAction(
              title: state is DownloadWalletFailure
                  ? appLocalizationsOf(context).tryAgain
                  : appLocalizationsOf(context).download,
              isLoading: state is DownloadWalletLoading,
              action: () {
                context
                    .read<DownloadWalletBloc>()
                    .add(DownloadWallet(_passwordController.text));
              },
            ),
          ],
        );
      },
    );
  }
}

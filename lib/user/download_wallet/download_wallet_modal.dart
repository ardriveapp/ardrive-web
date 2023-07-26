import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/download_wallet/bloc/download_wallet_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void showDownloadWalletModal(BuildContext context) {
  showAnimatedDialog(
    context,
    content: BlocProvider<DownloadWalletBloc>(
      create: (_) => DownloadWalletBloc(
        ardriveAuth: context.read<ArDriveAuth>(),
        ardriveIOUtils: ArDriveIOUtils(),
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
    return ArDriveStandardModal(
      title: appLocalizationsOf(context).downloadWalletKeyfile,
      content: BlocListener<DownloadWalletBloc, DownloadWalletState>(
        listener: (context, state) {
          if (state is DownloadWalletSuccess) {
            Navigator.of(context).pop();
          } else if (state is DownloadWalletFailure) {
            showAnimatedDialog(
              context,
              content: ArDriveStandardModal(
                title: appLocalizationsOf(context).error,
                content: Text(
                  appLocalizationsOf(context)
                      .anErrorOccuredWhileDownloadingYourKeyfile,
                  style: ArDriveTypography.body.buttonLargeBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  ),
                ),
                actions: [
                  ModalAction(
                    title: appLocalizationsOf(context).ok,
                    action: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            );
          }
        },
        child: BlocBuilder<DownloadWalletBloc, DownloadWalletState>(
          builder: (context, state) {
            return Column(
              children: [
                if (state is DownloadWalletWrongPassword) ...[
                  Text(
                    appLocalizationsOf(context).validationPasswordIncorrect,
                    style: ArDriveTypography.body.buttonLargeBold(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeErrorDefault,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                ArDriveTextField(
                  autofocus: true,
                  controller: _passwordController,
                  label: appLocalizationsOf(context).pleaseEnterYourPassword,
                  obscureText: true,
                  showObfuscationToggle: true,
                  onFieldSubmitted: (_) {
                    context
                        .read<DownloadWalletBloc>()
                        .add(DownloadWallet(_passwordController.text));
                  },
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        ModalAction(
          title: appLocalizationsOf(context).cancel,
          action: () {
            Navigator.of(context).pop();
          },
        ),
        ModalAction(
          title: appLocalizationsOf(context).enter,
          action: () {
            context
                .read<DownloadWalletBloc>()
                .add(DownloadWallet(_passwordController.text));
          },
        ),
      ],
    );
  }
}

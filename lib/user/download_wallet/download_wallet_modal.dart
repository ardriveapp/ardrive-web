import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/user/download_wallet/bloc/download_wallet_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void showDownloadWalletModal(BuildContext context) {
  showArDriveDialog(
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
    return BlocConsumer<DownloadWalletBloc, DownloadWalletState>(
      listener: (context, state) {
        if (state is DownloadWalletSuccess) {
          Navigator.of(context).pop();
        } else if (state is DownloadWalletFailure) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModalNew(
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
      builder: (context, state) {
        final typography = ArDriveTypographyNew.of(context);
        return ArDriveStandardModalNew(
          title: appLocalizationsOf(context).downloadWalletKeyfile,
          content: Column(
            children: [
              if (state is DownloadWalletWrongPassword) ...[
                Text(
                  appLocalizationsOf(context).validationPasswordIncorrect,
                  style: typography.paragraphLarge(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              ArDriveTextFieldNew(
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
              const SizedBox(height: 16),
              ArDriveClickArea(
                child: GestureDetector(
                  onTap: () {
                    openUrl(
                      url: Resources.howDoesKeyFileLoginWork,
                    );
                  },
                  child: Text(
                    appLocalizationsOf(context).whatIsAKeyFile,
                    style: ArDriveTypography.body
                        .buttonNormalRegular()
                        .copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              )
            ],
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
              isEnable: state is! DownloadWalletLoading,
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

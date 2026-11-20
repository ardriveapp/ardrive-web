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
    // It decrypts and saves: not closed by a tap outside while that runs.
    barrierDismissible: false,
    content: BlocProvider<DownloadWalletBloc>(
      create: (_) => DownloadWalletBloc(
        ardriveAuth: context.read<ArDriveAuth>(),
        ardriveIOUtils: ioUtils ?? ArDriveIOUtils(),
      ),
      child: const DownloadWalletModal(),
    ),
  );
}

class DownloadWalletModal extends StatefulWidget {
  const DownloadWalletModal({super.key});

  @override
  State<DownloadWalletModal> createState() => _DownloadWalletModalState();
}

class _DownloadWalletModalState extends State<DownloadWalletModal> {
  final _passwordController = TextEditingController();

  /// Set the moment a download is asked for, before the bloc has emitted its
  /// busy state: a second press in that gap would start a second download.
  bool _inFlight = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _download(DownloadWalletState state) {
    if (_inFlight || state is DownloadWalletLoading) return;
    setState(() => _inFlight = true);
    context.read<DownloadWalletBloc>().add(DownloadWallet(
          _passwordController.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DownloadWalletBloc, DownloadWalletState>(
      listener: (context, state) {
        if (state is! DownloadWalletLoading && _inFlight) {
          setState(() => _inFlight = false);
        }
        if (state is DownloadWalletSuccess) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        // The system Back button waits while the download runs.
        return PopScope(
            canPop: !_busy(state),
            child: ArDriveStandardModalNew(
              title: appLocalizationsOf(context).downloadWalletKeyfile,
              content: Column(
                children: [
                  ArDriveTextFieldNew(
                    autofocus: true,
                    controller: _passwordController,
                    label: appLocalizationsOf(context).password,
                    errorMessage: state is DownloadWalletWrongPassword
                        ? appLocalizationsOf(context)
                            .validationPasswordIncorrect
                        : null,
                    isEnabled: !_busy(state),
                    obscureText: true,
                    showObfuscationToggle: true,
                    onFieldSubmitted: (_) => _download(state),
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
                  isEnable: !_busy(state),
                  action: () {
                    Navigator.of(context).pop();
                  },
                ),
                ModalAction(
                  title: state is DownloadWalletFailure
                      ? appLocalizationsOf(context).tryAgain
                      : appLocalizationsOf(context).download,
                  isLoading: _busy(state),
                  action: () => _download(state),
                ),
              ],
            ));
      },
    );
  }

  bool _busy(DownloadWalletState state) =>
      _inFlight || state is DownloadWalletLoading;
}

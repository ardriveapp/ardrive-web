import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/authentication/login/views/modals/enter_your_password_modal.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider_wallet.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SecureYourWalletWidget extends StatefulWidget {
  const SecureYourWalletWidget(
      {super.key,
      required this.loginBloc,
      required this.wallet,
      this.derivedEthWallet,
      this.mnemonic,
      required this.showTutorials,
      required this.showWalletCreated});

  final Wallet wallet;
  final EthereumProviderWallet? derivedEthWallet;
  final String? mnemonic;
  final LoginBloc loginBloc;
  final bool showTutorials;
  final bool showWalletCreated;

  @override
  State<SecureYourWalletWidget> createState() => _SecureYourWalletWidgetState();
}

class _SecureYourWalletWidgetState extends State<SecureYourWalletWidget> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<ArDriveFormNewState>();
  bool _isPasswordValid = false;
  bool _confirmPasswordIsValid = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.createAndConfirmPasswordPage,
    );

    widget.wallet.getAddress().then((walletAddress) {
      logger.d('Loading profile name for anonymous user $walletAddress');

      context
          .read<ProfileNameBloc>()
          .add(LoadProfileNameAnonymous(walletAddress));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final showDerivedWalletNotYetCreated =
        widget.derivedEthWallet != null && widget.loginBloc.existingUserFlow;

    return SingleChildScrollView(
      child: ArDriveLoginModal(
        width: 450,
        onClose: () {
          if (_isProcessing) return;
          Navigator.of(context).pop();
          widget.loginBloc.add(const ForgetWallet());
        },
        content: ArDriveFormNew(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ArDriveImage(
                  image: AssetImage(Resources.images.brand.logo1),
                  height: 36,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  'Secure Your Wallet',
                  style: typography.heading2(
                      color: colorTokens.textHigh,
                      fontWeight: ArFontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                  showDerivedWalletNotYetCreated
                      ? 'We could not find a wallet for that Ethereum address, but you can create one now by entering a password to secure the new wallet.'
                      : 'Please enter and confirm a password to secure your wallet.',
                  textAlign: TextAlign.center,
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(height: 32),
              if (!widget.showTutorials)
                BlocBuilder<ProfileNameBloc, ProfileNameState>(
                  builder: (context, state) {
                    if (state is ProfileNameLoaded) {
                      return ProfileCardHeader(
                        walletAddress: state.walletAddress,
                        onPressed: () {},
                        isExpanded: true,
                        hasLogoutButton: true,
                        logoutTooltip: 'Forget wallet',
                        onClickLogout: () {
                          showArDriveDialog(context,
                              content: ForgetWalletDialog(
                                  loginBloc: widget.loginBloc));
                        },
                      );
                    }

                    return ProfileCardHeader(
                      walletAddress: state.walletAddress ?? '',
                      onPressed: () {},
                      isExpanded: true,
                      hasLogoutButton: true,
                      logoutTooltip: 'Forget wallet',
                      onClickLogout: () {
                        showArDriveDialog(context,
                            content: ForgetWalletDialog(
                                loginBloc: widget.loginBloc));
                      },
                    );
                  },
                ),
              const SizedBox(height: 32),
              Text('Password',
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(height: 8),
              ArDriveTextFieldNew(
                controller: _passwordController,
                hintText: 'Enter your password',
                showObfuscationToggle: true,
                obscureText: true,
                autofocus: true,
                autofillHints: const [AutofillHints.password],
                onChanged: (s) {
                  _formKey.currentState?.validate();
                },
                textInputAction: TextInputAction.next,
                isEnabled: !_isProcessing,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    setState(() {
                      _isPasswordValid = false;
                    });
                    return appLocalizationsOf(context).validationRequired;
                  }

                  setState(() {
                    _isPasswordValid = true;
                  });

                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text('Confirm Password',
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(height: 8),
              ArDriveTextFieldNew(
                  controller: _confirmPasswordController,
                  hintText: 'Re-enter your password',
                  showObfuscationToggle: true,
                  obscureText: true,
                  autofocus: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  isEnabled: !_isProcessing,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      setState(() {
                        _confirmPasswordIsValid = false;
                      });
                      return appLocalizationsOf(context).validationRequired;
                    } else if (value != _passwordController.text) {
                      setState(() {
                        _confirmPasswordIsValid = false;
                      });
                      return appLocalizationsOf(context).passwordMismatch;
                    }

                    setState(() {
                      _confirmPasswordIsValid = true;
                    });

                    return null;
                  },
                  onFieldSubmitted: (_) async {
                    if (_isPasswordValid && _confirmPasswordIsValid) {
                      _onSubmit();
                    }
                  }),
              const SizedBox(height: 40),
              ArDriveButtonNew(
                  text: 'Continue',
                  typography: typography,
                  variant: ButtonVariant.primary,
                  isDisabled: !_isPasswordValid ||
                      !_confirmPasswordIsValid ||
                      _isProcessing,
                  onPressed: () {
                    PlausibleEventTracker.trackClickConfirmPassword();
                    _onSubmit();
                  }),
            ],
          ),
        ),
      ),
    );
  }

  void _onSubmit() {
    final isValid = _formKey.currentState!.validateSync();

    if (!isValid) {
      showErrorDialog(
          context: context,
          title: appLocalizationsOf(context).error,
          message: appLocalizationsOf(context).passwordDoNotMatch);
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      showErrorDialog(
          context: context,
          title: appLocalizationsOf(context).error,
          message: appLocalizationsOf(context).passwordDoNotMatch);
      return;
    }

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.createdAndConfirmedPassword,
    );

    setState(() {
      _isProcessing = true;
    });

    if (widget.wallet is EthereumProviderWallet) {
      Navigator.of(context).pop();
    }

    widget.loginBloc.add(
      CreatePassword(
          password: _passwordController.text,
          wallet: widget.wallet,
          derivedEthWallet: widget.derivedEthWallet,
          mnemonic: widget.mnemonic,
          showTutorials: widget.showTutorials,
          showWalletCreated: widget.showWalletCreated),
    );
  }
}

void showSecureYourPasswordDialog(
    {required BuildContext context,
    required LoginBloc loginBloc,
    required Wallet wallet,
    EthereumProviderWallet? derivedEthWallet,
    String? mnemonic,
    required bool showTutorials,
    required bool showWalletCreated}) {
  showArDriveDialog(context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: BlocBuilder(
        bloc: loginBloc,
        buildWhen: (previous, current) {
          if (current is LoginCreatePasswordComplete) {
            Navigator.of(context).pop();
            return false;
          }
          return true;
        },
        builder: (context, state) {
          return SecureYourWalletWidget(
              loginBloc: loginBloc,
              wallet: wallet,
              derivedEthWallet: derivedEthWallet,
              mnemonic: mnemonic,
              showTutorials: showTutorials,
              showWalletCreated: showWalletCreated);
        },
      ));
}

import 'package:ardrive/authentication/components/biometric_toggle.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider_wallet.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_view_block.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class EnterYourPasswordWidget extends StatefulWidget {
  const EnterYourPasswordWidget({
    super.key,
    required this.loginBloc,
    required this.wallet,
    this.derivedEthWallet,
    this.sourceWalletAddress,
    required this.showWalletCreated,
    required this.checkingPassword,
    required this.passwordFailed,
    this.selectPassword = false,
  });

  /// The wallet just chosen. The account already on this device is
  /// unlocked in the sign-in panel instead, Welcome back.
  final Wallet wallet;
  final EthereumProviderWallet? derivedEthWallet;
  final String? sourceWalletAddress;
  final LoginBloc loginBloc;
  final bool showWalletCreated;
  final bool checkingPassword;
  final bool passwordFailed;

  /// Back from "Try again": focus the field with what was typed selected.
  final bool selectPassword;

  @override
  State<EnterYourPasswordWidget> createState() =>
      _EnterYourPasswordWidgetState();
}

class _EnterYourPasswordWidgetState extends State<EnterYourPasswordWidget> {
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode(debugLabel: 'signInPassword');
  // final _formKey = GlobalKey<ArDriveFormState>();
  bool _isPasswordValid = false;
  bool _isPasswordFailed = false;

  @override
  void initState() {
    super.initState();
    _isPasswordFailed = widget.passwordFailed;
    PlausibleEventTracker.trackPageview(
      page: _getPlausiblePageView(),
    );
  }

  PlausiblePageView _getPlausiblePageView() =>
      PlausiblePageView.enterPasswordPage;

  @override
  void didUpdateWidget(EnterYourPasswordWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    setState(() {
      _isPasswordFailed = widget.passwordFailed;
    });

    if (widget.selectPassword && !oldWidget.selectPassword) {
      // After the frame: the field is disabled until this rebuild lands.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _passwordFocus.requestFocus();
        _passwordController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _passwordController.text.length,
        );
      });
    }
  }

  @override
  void dispose() {
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Whether the profile name has been asked for. Once is enough: the wallet
  /// does not change while the modal is up.
  bool _profileNameRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This runs again whenever an inherited dependency changes, so it asks
    // once. And it takes the bloc now, before
    // the wait: the address can come from the database, the dialog closes as
    // soon as the login succeeds, and by the time the address arrives this
    // widget can be gone, taking `context` with it.
    if (_profileNameRequested) return;
    _profileNameRequested = true;
    final profileNameBloc = context.read<ProfileNameBloc>();
    _getWalletAddress().then((walletAddress) {
      logger.d('Loading profile name for anonymous user $walletAddress');
      profileNameBloc.add(LoadProfileNameBeforeLogin(walletAddress ?? ''));
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: _buildContent(width: 450, context: context),
    );
  }

  /// Back to Log in with this wallet dropped. Nothing stored on this
  /// device is forgotten unless this sign-in stored it ([LeaveWallet]). Not
  /// while the password is being checked: that check would still finish and
  /// sign in behind Log in.
  void _leave() {
    if (widget.checkingPassword) return;
    Navigator.of(context).pop();
    widget.loginBloc.add(const LeaveWallet(toLogIn: true));
  }

  Widget _buildContent({
    required double width,
    required BuildContext context,
  }) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveLoginModal(
      width: width,
      hasSettingsButton: true,
      // Hidden while the password is checked, as the link is off then.
      hasCloseButton: !widget.checkingPassword,
      onClose: () {
        PlausibleEventTracker.trackClickDismissLoginModalIcon(
          _getPlausiblePageView(),
        );
        _leave();
      },
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
              child: ArDriveImage(
            image: AssetImage(Resources.images.brand.logo1),
            height: 36,
          )),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.topCenter,
            child: Text(
              'Welcome back',
              style: typography.heading2(
                  color: colorTokens.textHigh, fontWeight: ArFontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Enter your password to unlock your drives.',
            textAlign: TextAlign.center,
            style: typography.paragraphNormal(
                color: colorTokens.textLow, fontWeight: ArFontWeight.semiBold),
          ),
          const SizedBox(height: 24),
          BlocBuilder<ProfileNameBloc, ProfileNameState>(
            builder: (context, state) {
              if (state is ProfileNameLoaded) {
                return ProfileCardHeader(
                  walletAddress: state.walletAddress,
                  onPressed: () {
                    openWalletExplorer(state.walletAddress,
                        isArweave: widget.sourceWalletAddress == null);
                  },
                  isExpanded: true,
                );
              }

              return ProfileCardHeader(
                walletAddress: state.walletAddress ?? '',
                onPressed: () {
                  if (state.walletAddress != null) {
                    openWalletExplorer(state.walletAddress!,
                        isArweave: widget.sourceWalletAddress == null);
                  }
                },
                isExpanded: true,
              );
            },
          ),
          const SizedBox(height: ArDriveSpacing.sm),
          // Leaving this wallet forgets nothing stored on this device: it
          // was a round X beside the address, read as "close" or "clear".
          Center(
            child: ArDriveLink(
              key: const Key('useDifferentWallet'),
              text: appLocalizationsOf(context).useDifferentWallet,
              isAction: true,
              onTap: widget.checkingPassword ? null : _leave,
            ),
          ),
          const SizedBox(height: ArDriveSpacing.xl),
          Text('Password',
              style: typography.paragraphNormal(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold)),
          const SizedBox(height: 8),
          ArDriveTextFieldNew(
            key: const Key('signInPassword'),
            controller: _passwordController,
            focusNode: _passwordFocus,
            hintText: 'Enter your password',
            showObfuscationToggle: true,
            obscureText: true,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            isEnabled: !widget.checkingPassword,
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
            onFieldSubmitted: (_) async {
              if (_isPasswordValid) {
                PlausibleEventTracker.trackPressEnterContinueReturnUser();
                _onSubmit();
              }
            },
            onChanged: (_) {
              setState(() {
                _isPasswordFailed = false;
              });
            },
            errorMessage: 'Invalid password. Please try again.',
            showErrorMessage: _isPasswordFailed,
          ),
          Align(
            alignment: Alignment.center,
            child: BiometricToggle(
              padding: const EdgeInsets.only(top: 40),
              onEnableBiometric: () {
                context.read<LoginBloc>().add(const UnLockWithBiometrics());
              },
            ),
          ),
          const Flexible(child: SizedBox(height: 40)),
          // Proving the password is not instant and never was: it finds a
          // private drive transaction, reads that drive's signature from the
          // gateway, derives a key and then fetches and decrypts the drive
          // entity - three network round trips and a key derivation, which on
          // a slow gateway runs to several seconds. The bloc has always
          // reported the phase as `LoginCheckingPassword`; the only thing this
          // screen did with it was grey the button out, which is
          // indistinguishable from a press that did not register. Now it says
          // what it is doing while it does it.
          ArDriveButtonNew(
              size: ArDriveButtonSize.large,
              maxWidth: double.infinity,
              text: 'Continue',
              // The spinner and the label as one centred group, rather than a
              // spinner pinned to the left edge with the label centred in what
              // is left of the button.
              customContent: widget.checkingPassword
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ArDriveSpinner(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colorTokens
                              .textLow,
                        ),
                        const SizedBox(width: 10),
                        // Flexible so a narrow button ellipsises the label
                        // rather than overflowing the row, and in the button's
                        // own text style so the busy state is the same weight
                        // and size as the label it replaces.
                        Flexible(
                          child: Text(
                            appLocalizationsOf(context).loginCheckingPassword,
                            overflow: TextOverflow.ellipsis,
                            style: typography.paragraphLarge(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colorTokens
                                  .textLow,
                              fontWeight: ArFontWeight.semiBold,
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
              typography: typography,
              variant: ButtonVariant.primary,
              isDisabled: !_isPasswordValid || widget.checkingPassword,
              onPressed: () {
                if (_isPasswordValid) {
                  PlausibleEventTracker.trackClickContinueLoginButton();

                  _onSubmit();
                }
              }),
        ],
      ),
    );
  }

  Future<String?> _getWalletAddress() async =>
      widget.sourceWalletAddress ?? await widget.wallet.getAddress();

  void _onSubmit() {
    if (widget.wallet is EthereumProviderWallet) {
      Navigator.of(context).pop();
    }
    widget.loginBloc.add(LoginWithPassword(
        password: _passwordController.text,
        wallet: widget.wallet,
        derivedEthWallet: widget.derivedEthWallet,
        showWalletCreated: widget.showWalletCreated));
  }
}

void showEnterYourPasswordDialog(
    {required BuildContext context,
    required LoginBloc loginBloc,
    required Wallet wallet,
    EthereumProviderWallet? derivedEthWallet,
    String? sourceWalletAddress,
    bool showWalletCreated = false,
    required bool isPasswordInvalid}) {
  showArDriveDialog(context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: BlocBuilder(
        bloc: loginBloc,
        buildWhen: (previous, current) {
          if (current is LoginSuccess) {
            Navigator.of(context).pop();
            return false;
          }
          return (current is GatewayLoginFailure ||
              current is LoginPasswordFailedWithPrivateDriveNotFound ||
              current is LoginCheckingPassword ||
              current is LoginPasswordFailed ||
              current is LoginPasswordOpensNoDrives ||
              current is LoginPasswordRetry ||
              current is LoginWithPassword ||
              current is LoginUnknownFailure);
        },
        builder: (context, state) {
          final checkingPassword = state is LoginCheckingPassword;
          final passwordFailed =
              state is LoginPasswordFailed || isPasswordInvalid;

          return EnterYourPasswordWidget(
            loginBloc: loginBloc,
            wallet: wallet,
            derivedEthWallet: derivedEthWallet,
            sourceWalletAddress: sourceWalletAddress,
            showWalletCreated: showWalletCreated,
            checkingPassword: checkingPassword,
            passwordFailed: passwordFailed,
            selectPassword: state is LoginPasswordRetry,
          );
        },
      ));
}

class ForgetWalletDialog extends StatelessWidget {
  const ForgetWalletDialog({
    super.key,
    required this.loginBloc,
    this.closesDialogBelow = true,
  });

  final LoginBloc loginBloc;

  /// Whether Confirm also closes the dialog this one opened over. False when
  /// it opened over the sign-in panel itself.
  final bool closesDialogBelow;

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: 'Forget wallet',
      description: 'Are you sure you want to forget this wallet?',
      actions: [
        ModalAction(
          title: 'Cancel',
          action: () {
            Navigator.of(context).pop();
          },
        ),
        ModalAction(
          title: 'Confirm',
          action: () {
            Navigator.of(context).pop();
            if (closesDialogBelow) Navigator.of(context).pop();
            loginBloc.add(const ForgetWallet());
            context.read<ProfileNameBloc>().add(const CleanProfileName());
            PlausibleEventTracker.trackClickForgetWalletTextButton();
          },
        ),
      ],
    );
  }
}

/// The sign-in password opened none of the wallet's private drives.
///
/// Not a wrong password: drive passwords are separate from the sign-in one,
/// so the user may correct it or go on with those drives locked. Shown for
/// [LoginPasswordOpensNoDrives].
Future<void> showPasswordOpensNoDrivesDialog({
  required BuildContext context,
  required LoginBloc loginBloc,
}) =>
    showArDriveDialog(
      context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: PasswordOpensNoDrivesDialog(loginBloc: loginBloc),
    );

class PasswordOpensNoDrivesDialog extends StatelessWidget {
  const PasswordOpensNoDrivesDialog({super.key, required this.loginBloc});

  final LoginBloc loginBloc;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);

    return ArDriveStandardModalNew(
      key: const Key('passwordOpensNoDrivesDialog'),
      title: strings.passwordOpensNoDrivesTitle,
      description: strings.passwordOpensNoDrivesBody,
      actions: [
        ModalAction.dismiss(
          title: strings.tryAgain,
          action: () {
            Navigator.of(context).pop();
            loginBloc.add(const RetrySignInPassword());
          },
        ),
        ModalAction(
          title: strings.continueEmphasized,
          action: () {
            Navigator.of(context).pop();
            loginBloc.add(const ContinueSignInWithLockedDrives());
          },
        ),
      ],
    );
  }
}

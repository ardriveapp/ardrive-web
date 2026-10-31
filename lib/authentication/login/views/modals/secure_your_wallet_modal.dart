import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:ardrive/authentication/password/new_password.dart';
import 'package:ardrive/authentication/password/new_password_fields.dart';
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

class SecureYourWalletWidget extends StatefulWidget {
  const SecureYourWalletWidget(
      {super.key,
      required this.loginBloc,
      required this.wallet,
      this.derivedEthWallet,
      this.sourceWalletAddress,
      this.mnemonic,
      required this.isNewUser,
      required this.showWalletCreated,
      this.retrying = false,
      this.fromSignUp = false,
      this.breachCheck});

  final Wallet wallet;
  final EthereumProviderWallet? derivedEthWallet;
  final String? sourceWalletAddress;
  final String? mnemonic;
  final LoginBloc loginBloc;
  final bool isNewUser;
  final bool showWalletCreated;

  /// The last try to finish with this password could not; says so.
  final bool retrying;

  /// A browser wallet chosen from Sign up: a new ArDrive account.
  final bool fromSignUp;

  /// Asks whether a typed password is in a known breach. Replaced in tests.
  final BreachedPasswordCheck? breachCheck;

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

  /// The passphrase last suggested, while it is what the field holds.
  String? _suggestion;

  /// Whether both fields hide what they hold. One eye, on the password
  /// field, controls both, and only it: a suggestion fills both fields
  /// masked, as a phone's screen may be seen or recorded.
  bool _obscured = true;
  PasswordStrength? _strength;

  /// An account being made now, whose password locks everything it will
  /// keep: one Sign up made, a browser wallet chosen from Sign up, or a new
  /// MetaMask account, whose wallet is derived from it. It must be strong
  /// and not in a known breach, and one can be suggested. Anyone else,
  /// including a wallet from Log in that has no drives yet, keeps whatever
  /// password they have.
  bool get _rulesApply =>
      widget.fromSignUp ||
      (widget.isNewUser &&
          (widget.mnemonic != null || widget.derivedEthWallet != null));

  /// A password the breach check found, so the field says so until changed.
  String? _breachedPassword;

  /// An account made here, with nothing to show yet: no wallet card.
  bool get _isFreshAccount =>
      widget.isNewUser &&
      widget.mnemonic != null &&
      widget.sourceWalletAddress == null;

  Future<void> _suggest() async {
    final words = await loadPassphraseWords(DefaultAssetBundle.of(context));
    if (!mounted) return;
    final phrase = suggestPassphrase(words);
    // The caret after it, not the whole of it selected.
    final filled = TextEditingValue(
      text: phrase,
      selection: TextSelection.collapsed(offset: phrase.length),
    );
    _passwordController.value = filled;
    _confirmPasswordController.value = filled;
    // Filled in, not typed: no field validator runs, and none needs to. A
    // suggestion is strong and the same in both fields.
    setState(() {
      _suggestion = phrase;
      _strength = PasswordStrength.strong;
      _isPasswordValid = true;
      _confirmPasswordIsValid = true;
    });
  }

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.createAndConfirmPasswordPage,
    );

    final displayAddress = widget.sourceWalletAddress;
    if (displayAddress != null) {
      logger.d('Loading profile name for source wallet $displayAddress');
      context
          .read<ProfileNameBloc>()
          .add(LoadProfileNameBeforeLogin(displayAddress));
    } else {
      // Taken before the wait: the modal can close before the address
      // arrives, and `context` goes with it.
      final profileNameBloc = context.read<ProfileNameBloc>();
      widget.wallet.getAddress().then((walletAddress) {
        logger.d('Loading profile name for anonymous user $walletAddress');
        profileNameBloc.add(LoadProfileNameBeforeLogin(walletAddress));
      });
    }
  }

  String _getDescription() {
    final isReturning = !widget.isNewUser;
    final chainName = widget.sourceWalletAddress != null
        ? (widget.sourceWalletAddress!.startsWith('0x') ? 'Ethereum' : 'Solana')
        : null;

    if (!isReturning && chainName == null) {
      return appLocalizationsOf(context).newPasswordBody;
    }
    if (isReturning && chainName != null) {
      return 'We found your drives! Enter a password to encrypt '
          'your private files. This password can never be changed, '
          'reset, or recovered.';
    } else if (isReturning) {
      return 'We found your drives! Enter a password to encrypt '
          'your private files. This password can never be changed, '
          'reset, or recovered.';
    } else if (chainName != null) {
      return 'ArDrive creates a secure storage wallet linked to your '
          '$chainName wallet. Enter a password to encrypt your '
          'private files. This password can never be changed, '
          'reset, or recovered.';
    }
    return 'Please enter and confirm a password to secure your wallet. '
        'This password is used to encrypt your private files, and can '
        'never be changed, reset, or recovered. Be sure to store it '
        'somewhere safe.';
  }

  /// Leaves this wallet, back to the first panel as it always went. Nothing
  /// stored on this device is forgotten unless this flow stored it
  /// ([LeaveWallet]): closing a sign-up a returning user had reached used to
  /// sign them out and delete their own account.
  void _leave() {
    if (_isProcessing) return;
    Navigator.of(context).pop();
    widget.loginBloc.add(const LeaveWallet());
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return SingleChildScrollView(
      child: ArDriveLoginModal(
        width: 450,
        onClose: _leave,
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
              const SizedBox(height: ArDriveSpacing.sm),
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  // A wallet chosen from Sign up is making an account here,
                  // under the new-account rules, even if it has drives.
                  widget.isNewUser || widget.fromSignUp
                      ? appLocalizationsOf(context).newPasswordTitle
                      : 'Welcome back',
                  style: typography.heading2(
                      color: colorTokens.textHigh,
                      fontWeight: ArFontWeight.bold),
                ),
              ),
              const SizedBox(height: ArDriveSpacing.xs),
              Text(_getDescription(),
                  textAlign: TextAlign.center,
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              if (_isFreshAccount) ...[
                const SizedBox(height: ArDriveSpacing.xs),
                Text(
                  appLocalizationsOf(context).newPasswordRecoveryNote,
                  key: const Key('newPasswordRecoveryNote'),
                  textAlign: TextAlign.center,
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold),
                ),
              ],
              if (widget.retrying) ...[
                const SizedBox(height: ArDriveSpacing.md),
                ArDriveNotice(
                  key: const Key('newPasswordRetry'),
                  type: ArDriveNoticeType.error,
                  message: appLocalizationsOf(context).newPasswordRetry,
                ),
              ],
              if (!_isFreshAccount) ...[
                const SizedBox(height: ArDriveSpacing.lg),
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
                // Leaving this wallet forgets nothing stored on this device:
                // it was a round X beside the address, read as "close".
                Center(
                  child: ArDriveLink(
                    key: const Key('useDifferentWallet'),
                    text: appLocalizationsOf(context).useDifferentWallet,
                    isAction: true,
                    onTap: _leave,
                  ),
                ),
              ],
              const SizedBox(height: ArDriveSpacing.lg),
              Text('Password',
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(height: ArDriveSpacing.xs),
              ArDriveTextFieldNew(
                controller: _passwordController,
                key: const Key('signUpPassword'),
                hintText: 'Enter your password',
                obscureText: _obscured,
                suffixIcon: PasswordRevealToggle(
                  key: const Key('signUpPasswordReveal'),
                  obscured: _obscured,
                  onToggle: () => setState(() => _obscured = !_obscured),
                ),
                autofocus: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                isEnabled: !_isProcessing,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    setState(() {
                      _isPasswordValid = false;
                      _strength = null;
                    });
                    return appLocalizationsOf(context).validationRequired;
                  }

                  if (_rulesApply) {
                    final strength = assessNewPassword(value);
                    final strong = strength == PasswordStrength.strong;
                    setState(() {
                      _strength = strength;
                      _isPasswordValid = strong;
                      if (_suggestion != null && value != _suggestion) {
                        _suggestion = null;
                      }
                    });
                    final s = appLocalizationsOf(context);
                    if (strong && value == _breachedPassword) {
                      setState(() => _isPasswordValid = false);
                      return s.newPasswordBreached;
                    }
                    return switch (strength) {
                      PasswordStrength.tooShort => s.newPasswordTooShort,
                      PasswordStrength.weak => s.newPasswordWeak,
                      PasswordStrength.fair => s.newPasswordFair,
                      PasswordStrength.strong => null,
                    };
                  }

                  setState(() {
                    _isPasswordValid = true;
                  });

                  return null;
                },
              ),
              if (_rulesApply && _strength != null) ...[
                const SizedBox(height: ArDriveSpacing.xs),
                PasswordStrengthMeter(strength: _strength!),
              ],
              if (_rulesApply) ...[
                const SizedBox(height: ArDriveSpacing.sm),
                if (_suggestion == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ArDriveButtonNew(
                      key: const Key('suggestPasswordButton'),
                      size: ArDriveButtonSize.compact,
                      text: appLocalizationsOf(context).newPasswordSuggest,
                      typography: typography,
                      variant: ButtonVariant.secondary,
                      isDisabled: _isProcessing,
                      onPressed: _suggest,
                    ),
                  )
                else
                  SuggestedPassphrase(
                    phrase: _suggestion!,
                    onAnother: _isProcessing ? null : _suggest,
                  ),
              ],
              const SizedBox(height: ArDriveSpacing.md),
              Text('Confirm password',
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(height: ArDriveSpacing.xs),
              ArDriveTextFieldNew(
                  controller: _confirmPasswordController,
                  key: const Key('signUpConfirmPassword'),
                  hintText: 'Re-enter your password',
                  obscureText: _obscured,
                  autofocus: true,
                  autofillHints: const [AutofillHints.newPassword],
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
              const SizedBox(height: ArDriveSpacing.lg),
              ArDriveButtonNew(
                  size: ArDriveButtonSize.large,
                  maxWidth: double.infinity,
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

  Future<void> _onSubmit() async {
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

    setState(() {
      _isProcessing = true;
    });

    // A suggestion is random and never in a breach; one typed may be.
    final password = _passwordController.text;
    if (_rulesApply && password != _suggestion) {
      final breached = await (widget.breachCheck ?? BreachedPasswordCheck())
          .isBreached(password);
      if (!mounted) return;
      if (breached == true) {
        setState(() {
          _isProcessing = false;
          _breachedPassword = password;
        });
        _formKey.currentState!.validateSync();
        return;
      }
    }

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.createdAndConfirmedPassword,
    );

    if (widget.wallet is EthereumProviderWallet) {
      Navigator.of(context).pop();
    }

    widget.loginBloc.add(
      CreatePassword(
          password: _passwordController.text,
          wallet: widget.wallet,
          derivedEthWallet: widget.derivedEthWallet,
          mnemonic: widget.mnemonic,
          isNewUser: widget.isNewUser,
          showWalletCreated: widget.showWalletCreated),
    );
  }
}

void showSecureYourPasswordDialog(
    {required BuildContext context,
    required LoginBloc loginBloc,
    required Wallet wallet,
    EthereumProviderWallet? derivedEthWallet,
    String? sourceWalletAddress,
    String? mnemonic,
    required bool isNewUser,
    required bool showWalletCreated,
    bool fromSignUp = false,
    bool retrying = false}) {
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
          if (current is LoginFailure ||
              current is LoginUnknownFailure ||
              current is GatewayLoginFailure) {
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
              sourceWalletAddress: sourceWalletAddress,
              mnemonic: mnemonic,
              isNewUser: isNewUser,
              showWalletCreated: showWalletCreated,
              fromSignUp: fromSignUp,
              retrying: retrying);
        },
      ));
}

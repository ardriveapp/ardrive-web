import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/authentication/login/views/modals/enter_your_password_modal.dart';
import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:ardrive/authentication/password/new_password.dart';
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
import 'package:flutter/services.dart';
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
  PasswordStrength? _strength;

  /// An account being made now, whose password locks everything it will
  /// keep: one from Sign up, or a new MetaMask account, whose wallet is
  /// derived from it. It must be strong and not in a known breach, and one
  /// can be suggested. Anyone else, including a returning wallet that has no
  /// drives yet, keeps whatever password they have.
  bool get _rulesApply =>
      widget.isNewUser &&
      (widget.mnemonic != null || widget.derivedEthWallet != null);

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
    _passwordController.text = phrase;
    _confirmPasswordController.text = phrase;
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

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

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
                  widget.isNewUser
                      ? appLocalizationsOf(context).newPasswordTitle
                      : 'Welcome back',
                  style: typography.heading2(
                      color: colorTokens.textHigh,
                      fontWeight: ArFontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(_getDescription(),
                  textAlign: TextAlign.center,
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              if (widget.retrying) ...[
                const SizedBox(height: 16),
                ArDriveNotice(
                  key: const Key('newPasswordRetry'),
                  type: ArDriveNoticeType.error,
                  message: appLocalizationsOf(context).newPasswordRetry,
                ),
              ],
              if (!_isFreshAccount) ...[
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
                      onPressed: () {
                        if (state.walletAddress != null) {
                          openWalletExplorer(state.walletAddress!,
                              isArweave: widget.sourceWalletAddress == null);
                        }
                      },
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
              ],
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
                      if (value != _suggestion) _suggestion = null;
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
                const SizedBox(height: 8),
                _StrengthMeter(strength: _strength!),
              ],
              if (_rulesApply) ...[
                const SizedBox(height: 12),
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
                  _SuggestedPassphrase(
                    phrase: _suggestion!,
                    onAnother: _isProcessing ? null : _suggest,
                  ),
              ],
              const SizedBox(height: 20),
              Text('Confirm password',
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
              retrying: retrying);
        },
      ));
}

/// Four bars and a word: how strong the new password looks.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final s = appLocalizationsOf(context);
    final (bars, colour, label) = switch (strength) {
      PasswordStrength.tooShort => (1, colors.statusErrorFg, s.passwordWeak),
      PasswordStrength.weak => (1, colors.statusErrorFg, s.passwordWeak),
      PasswordStrength.fair => (2, colors.textMid, s.passwordFair),
      PasswordStrength.strong => (4, colors.statusSuccessFg, s.passwordStrong),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i < bars ? colour : colors.strokeMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Text(
            label,
            style: type.paragraphSmall(
              color: colour,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        ],
      ),
    );
  }
}

/// The suggested passphrase, readable, with Copy and another suggestion.
/// It is made on the device and kept nowhere; saving it is up to the user.
class _SuggestedPassphrase extends StatelessWidget {
  const _SuggestedPassphrase({required this.phrase, required this.onAnother});

  final String phrase;
  final VoidCallback? onAnother;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final s = appLocalizationsOf(context);
    return Container(
      key: const Key('suggestedPassphrase'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.containerRaised,
        border: Border.all(color: colors.strokeMid),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            phrase,
            style: type.paragraphLarge(
              color: colors.textHigh,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.newPasswordSaveIt,
            style: type.paragraphSmall(color: colors.textMid),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              ArDriveLink(
                text: s.newPasswordCopy,
                isAction: true,
                onTap: () => Clipboard.setData(ClipboardData(text: phrase)),
              ),
              if (onAnother != null)
                ArDriveLink(
                  text: s.newPasswordSuggestAnother,
                  isAction: true,
                  onTap: onAnother!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

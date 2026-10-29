import 'package:ardrive/authentication/components/biometric_toggle.dart';
import 'package:ardrive/authentication/components/login_card.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/enter_your_password_modal.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Whether [state] tells the Welcome back panel something: that the
/// password is being checked, was wrong, or the check ended.
@visibleForTesting
bool welcomeBackHears(LoginState state) =>
    state is LoginCheckingPassword ||
    state is LoginPasswordFailed ||
    state is GatewayLoginFailure ||
    state is LoginUnknownFailure ||
    state is LoginFailure ||
    state is PromptPassword;

/// The sign-in panel after a reload, for the account already on this
/// device: its password unlocks it. Another account means forgetting this
/// one first.
class WelcomeBackView extends StatefulWidget {
  const WelcomeBackView({super.key});

  @override
  State<WelcomeBackView> createState() => _WelcomeBackViewState();
}

class _WelcomeBackViewState extends State<WelcomeBackView> {
  final _password = TextEditingController();

  /// The last try was the wrong password, and nothing has been typed since.
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.returnUserPage,
    );
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) return;
    PlausibleEventTracker.trackClickContinueReturnUserButton();
    context
        .read<LoginBloc>()
        .add(UnlockUserWithPassword(password: _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final loginBloc = context.read<LoginBloc>();

    return SizedBox(
      width: 381,
      child: LoginCard(
        content: BlocConsumer<LoginBloc, LoginState>(
          listenWhen: (_, current) => welcomeBackHears(current),
          listener: (context, state) =>
              setState(() => _wrong = state is LoginPasswordFailed),
          buildWhen: (_, current) => welcomeBackHears(current),
          builder: (context, state) {
            final checking = state is LoginCheckingPassword;
            final wrong = _wrong && !checking;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ArDriveImage(
                    image: AssetImage(Resources.images.brand.logo1),
                    height: 50,
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.lg),
                Text(
                  s.welcomeBackTitle,
                  textAlign: TextAlign.center,
                  style: type.heading1(
                    color: colors.textHigh,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.xs),
                Text(
                  s.welcomeBackBody,
                  textAlign: TextAlign.center,
                  style: type.paragraphLarge(color: colors.textMid),
                ),
                const SizedBox(height: ArDriveSpacing.lg),
                Text(
                  s.password,
                  style: type.paragraphNormal(
                    color: colors.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.xs),
                ArDriveTextFieldNew(
                  key: const Key('welcomeBackPassword'),
                  controller: _password,
                  obscureText: true,
                  showObfuscationToggle: true,
                  autofocus: true,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.password],
                  isEnabled: !checking,
                  errorMessage: wrong ? s.welcomeBackWrongPassword : null,
                  showErrorMessage: wrong,
                  // Typing again clears the error and wakes the button.
                  onChanged: (_) => setState(() => _wrong = false),
                  onFieldSubmitted: (_) {
                    PlausibleEventTracker.trackPressEnterContinueReturnUser();
                    _submit();
                  },
                ),
                const SizedBox(height: ArDriveSpacing.md),
                ArDriveButtonNew(
                  key: const Key('welcomeBackLogIn'),
                  size: ArDriveButtonSize.large,
                  maxWidth: double.infinity,
                  typography: type,
                  text: s.logIn,
                  variant: ButtonVariant.primary,
                  isDisabled: _password.text.isEmpty || checking,
                  customContent: checking
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ArDriveSpinner(color: colors.textLow),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                s.loginCheckingPassword,
                                overflow: TextOverflow.ellipsis,
                                style: type.paragraphLarge(
                                  color: colors.textLow,
                                  fontWeight: ArFontWeight.semiBold,
                                ),
                              ),
                            ),
                          ],
                        )
                      : null,
                  onPressed: _submit,
                ),
                // Draws nothing where the device can't offer biometrics,
                // which includes every browser.
                Center(
                  child: BiometricToggle(
                    padding: const EdgeInsets.only(top: ArDriveSpacing.lg),
                    onEnableBiometric: () =>
                        loginBloc.add(const UnLockWithBiometrics()),
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.lg),
                Center(
                  child: ArDriveLink(
                    key: const Key('welcomeBackDifferentAccount'),
                    text: s.welcomeBackDifferentAccount,
                    isAction: true,
                    onTap: checking
                        ? null
                        : () => showArDriveDialog(
                              context,
                              content: ForgetWalletDialog(
                                loginBloc: loginBloc,
                                closesDialogBelow: false,
                              ),
                            ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

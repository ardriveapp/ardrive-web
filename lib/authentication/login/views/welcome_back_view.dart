import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/components/biometric_toggle.dart';
import 'package:ardrive/authentication/components/login_card.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/enter_your_password_modal.dart';
import 'package:ardrive/authentication/login/views/wallet_wait_view.dart';
import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show triggerHTMLPageReload;
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
    state is PromptPassword ||
    state is PromptWalletUnlock ||
    state is LoginProfileFromNewerVersion;

/// The sign-in panel after a reload, for the account already on this
/// device: its password unlocks it. Another account means forgetting this
/// one first.
class WelcomeBackView extends StatefulWidget {
  const WelcomeBackView({super.key, this.ready = true});

  /// False while the app is still checking for the account this view
  /// expects (`ProfileCubit.presence`): the password can be typed, and goes
  /// nowhere until the check is in. The same view then carries on, typed
  /// password and all.
  final bool ready;

  @override
  State<WelcomeBackView> createState() => _WelcomeBackViewState();
}

class _WelcomeBackViewState extends State<WelcomeBackView> {
  final _password = TextEditingController();

  /// The last try was the wrong password, and nothing has been typed since.
  bool _wrong = false;

  /// The account was saved by a newer ArDrive: only a reload helps, and
  /// nothing here may forget it.
  bool _savedByNewer = false;

  /// The account on this device, once read from it.
  String? _address;
  bool _addressAsked = false;

  /// For an account a browser wallet opens: what Welcome back asks, from
  /// the bloc, or read from the device while the check for the account is
  /// still running, so no password field shows for a moment first.
  PromptWalletUnlock? _walletPrompt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_addressAsked) return;
    _addressAsked = true;
    // Taken now: the panel can be gone by the time the address arrives.
    final profileName = context.read<ProfileNameBloc>();
    final auth = context.read<ArDriveAuth>();
    auth.getWalletAddress().then((address) {
      if (address == null || address.isEmpty) return;
      profileName.add(LoadProfileNameBeforeLogin(address));
      if (mounted) setState(() => _address = address);
    }).catchError((Object _) {});
    Future<SavedAccount?>.sync(auth.savedAccount).then((account) {
      final method = account?.walletMethod;
      if (!mounted || method == null || _walletPrompt != null) return;
      setState(() => _walletPrompt = PromptWalletUnlock(
            wallet: switch (method) {
              DeviceUnlockMethod.wander => BrowserWallet.wander,
              DeviceUnlockMethod.ethereum ||
              DeviceUnlockMethod.ethereumAccount =>
                BrowserWallet.metamask,
              _ => BrowserWallet.otherSolana,
            },
            relocks: account!.isLegacyWalletProfile,
          ));
    }).catchError((Object _) {});
  }

  @override
  void initState() {
    super.initState();
    if (widget.ready) _trackPageview();
  }

  @override
  void didUpdateWidget(WelcomeBackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) _trackPageview();
  }

  void _trackPageview() => PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.returnUserPage,
      );

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.ready || _password.text.isEmpty) return;
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
          listener: (context, state) => setState(() {
            if (state is PromptWalletUnlock) _walletPrompt = state;
            _wrong = state is LoginPasswordFailed;
            _savedByNewer =
                _savedByNewer || state is LoginProfileFromNewerVersion;
          }),
          buildWhen: (_, current) => welcomeBackHears(current),
          builder: (context, state) {
            if (_savedByNewer || state is LoginProfileFromNewerVersion) {
              return _SavedByNewerVersion(address: _address);
            }
            final walletPrompt =
                state is PromptWalletUnlock ? state : _walletPrompt;
            if (walletPrompt != null) {
              return _WalletUnlock(
                prompt: walletPrompt,
                address: _address,
                ready: widget.ready,
                onDifferentAccount: () => showArDriveDialog(
                  context,
                  content: ForgetWalletDialog(
                    loginBloc: loginBloc,
                    closesDialogBelow: false,
                  ),
                ),
              );
            }
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
                if (_address != null) ...[
                  _Account(address: _address!),
                  const SizedBox(height: ArDriveSpacing.xs),
                ],
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
                  isDisabled:
                      !widget.ready || _password.text.isEmpty || checking,
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
                    onEnableBiometric: () {
                      if (widget.ready) {
                        loginBloc.add(const UnLockWithBiometrics());
                      }
                    },
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.lg),
                Center(
                  child: ArDriveLink(
                    key: const Key('welcomeBackDifferentAccount'),
                    text: s.welcomeBackDifferentAccount,
                    isAction: true,
                    onTap: checking || !widget.ready
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

/// The account on this device was saved by a newer ArDrive than this tab
/// runs: say so, and offer only a reload. No sign-in, and no way to forget
/// the account, which this build can't read but a newer one can.
class _SavedByNewerVersion extends StatelessWidget {
  const _SavedByNewerVersion({required this.address});

  final String? address;

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    return Column(
      key: const Key('welcomeBackSavedByNewer'),
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
        if (address != null) ...[
          const SizedBox(height: ArDriveSpacing.xs),
          _Account(address: address!),
        ],
        const SizedBox(height: ArDriveSpacing.xs),
        Text(
          s.savedByNewerVersion,
          textAlign: TextAlign.center,
          style: type.paragraphLarge(color: colors.textMid),
        ),
        const SizedBox(height: ArDriveSpacing.lg),
        ArDriveButtonNew(
          key: const Key('welcomeBackReload'),
          size: ArDriveButtonSize.large,
          maxWidth: double.infinity,
          typography: type,
          text: s.reloadPage,
          variant: ButtonVariant.primary,
          onPressed: triggerHTMLPageReload,
        ),
      ],
    );
  }
}

/// The account the password unlocks: its ArNS name once loaded, and its
/// short address.
class _Account extends StatelessWidget {
  const _Account({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    return BlocBuilder<ProfileNameBloc, ProfileNameState>(
      builder: (context, state) {
        final name =
            state is ProfileNameLoaded && state.walletAddress == address
                ? state.primaryNameDetails.primaryName
                : null;
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: ArDriveSpacing.xs,
          children: [
            if (name != null)
              Text(
                name,
                style: type.paragraphNormal(
                  color: colors.textMid,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ArDriveIdText(
              shortenId(address),
              style: type.code(color: colors.textLow),
            ),
          ],
        );
      },
    );
  }
}

/// Welcome back for an account a browser wallet opens: one approval in
/// that wallet, never a password.
class _WalletUnlock extends StatelessWidget {
  const _WalletUnlock({
    required this.prompt,
    required this.address,
    required this.ready,
    required this.onDifferentAccount,
  });

  final PromptWalletUnlock prompt;
  final String? address;
  final bool ready;
  final VoidCallback onDifferentAccount;

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final name = WalletWaitView.nameOf(prompt.wallet);
    final problem = switch (prompt.problem) {
      null => null,
      WalletUnlockProblem.declined => s.welcomeBackDeclined,
      WalletUnlockProblem.mismatch => s.welcomeBackMismatch,
      WalletUnlockProblem.otherAccount => s.welcomeBackOtherAccount,
      WalletUnlockProblem.notThisAccount => s.welcomeBackNotThisAccount,
      WalletUnlockProblem.failed => s.welcomeBackFailed,
    };

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
        if (address != null) ...[
          _Account(address: address!),
          const SizedBox(height: ArDriveSpacing.xs),
        ],
        Text(
          s.welcomeBackWalletBody,
          textAlign: TextAlign.center,
          style: type.paragraphLarge(color: colors.textMid),
        ),
        if (prompt.relocks) ...[
          const SizedBox(height: ArDriveSpacing.md),
          ArDriveNotice(
            key: const Key('welcomeBackRelocks'),
            type: ArDriveNoticeType.info,
            message: s.welcomeBackRelocks,
          ),
        ],
        if (problem != null) ...[
          const SizedBox(height: ArDriveSpacing.md),
          ArDriveStatusText(
            key: const Key('welcomeBackWalletProblem'),
            text: problem,
            type: ArDriveStatusType.error,
          ),
        ],
        const SizedBox(height: ArDriveSpacing.lg),
        ArDriveButtonNew(
          key: const Key('welcomeBackContinueWithWallet'),
          size: ArDriveButtonSize.large,
          maxWidth: double.infinity,
          typography: type,
          text: name == null
              ? s.welcomeBackContinueGeneric
              : s.welcomeBackContinueWith(name),
          variant: ButtonVariant.primary,
          isDisabled: !ready,
          onPressed: () {
            PlausibleEventTracker.trackClickContinueReturnUserButton();
            context.read<LoginBloc>().add(const UnlockWithWallet());
          },
        ),
        const SizedBox(height: ArDriveSpacing.lg),
        Center(
          child: ArDriveLink(
            key: const Key('welcomeBackDifferentAccount'),
            text: s.welcomeBackDifferentAccount,
            isAction: true,
            onTap: ready ? onDifferentAccount : null,
          ),
        ),
      ],
    );
  }
}

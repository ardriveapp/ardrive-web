import 'package:ardrive/authentication/components/login_card.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/solana_wallet_picker_modal.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/solana/solana_provider.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

/// Log in, in the sign-in panel: an account made with ArDrive, by its
/// recovery phrase or keyfile, or a browser wallet. A wallet is offered only
/// when its extension is in this browser.
///
/// With [signUp] it is Sign up's choice instead, shown when a wallet was
/// found: a new account first, then the same wallets, which log in the same
/// way. A wallet ArDrive hasn't seen becomes a new account.
class LogInView extends StatefulWidget {
  const LogInView({
    super.key,
    required this.isArConnectAvailable,
    required this.isMetamaskAvailable,
    required this.isSolanaAvailable,
    this.signUp = false,
    this.detectSolanaWallets,
  });

  /// Sign up's choice rather than Log in.
  final bool signUp;

  final bool isArConnectAvailable;
  final bool isMetamaskAvailable;
  final bool isSolanaAvailable;

  /// Which Solana wallets are installed. Replaced in tests.
  final SolanaLoginProviderDetection Function()? detectSolanaWallets;

  @override
  State<LogInView> createState() => _LogInViewState();
}

class _LogInViewState extends State<LogInView> {
  // Its pageview is sent by the first panel's Log in, once per visit, not
  // each time this panel comes back after a wallet's Cancel.

  void _connectSolanaWallet(BuildContext context) {
    final loginBloc = context.read<LoginBloc>();
    final detection = widget.detectSolanaWallets?.call() ??
        SolanaProviderService().detectProviders();

    if (detection.hasPhantom && detection.hasSolflare) {
      showSolanaWalletPickerDialog(context: context, loginBloc: loginBloc);
    } else if (detection.hasPhantom) {
      loginBloc.add(const LoginWithSolana(provider: 'phantom'));
    } else if (detection.hasSolflare) {
      loginBloc.add(const LoginWithSolana(provider: 'solflare'));
    } else {
      loginBloc.add(const LoginWithSolana());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final loginBloc = context.read<LoginBloc>();
    final signUp = widget.signUp;
    final pageView =
        signUp ? PlausiblePageView.signUpPage : PlausiblePageView.loginPage;
    final anyWallet = widget.isArConnectAvailable ||
        widget.isMetamaskAvailable ||
        widget.isSolanaAvailable;

    return SizedBox(
      width: 381,
      child: LoginCard(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ArDriveLink(
                key: const Key('logInBack'),
                text: s.back,
                isAction: true,
                onTap: () => loginBloc.add(const ShowLanding()),
              ),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            Text(
              signUp ? s.signUpTitle : s.logIn,
              style: type.heading2(
                color: colors.textHigh,
                fontWeight: ArFontWeight.bold,
              ),
            ),
            if (!signUp) ...[
              const SizedBox(height: ArDriveSpacing.xs),
              Text(
                s.logInBody,
                style: type.paragraphNormal(color: colors.textMid),
              ),
            ],
            const SizedBox(height: ArDriveSpacing.lg),
            if (signUp)
              LogInOption(
                key: const Key('signUpCreateAccount'),
                icon: ArDriveIcons.plus(size: 20, color: colors.iconMid),
                label: s.logInCreateAccount,
                onPressed: () {
                  PlausibleEventTracker.trackClickCreateWallet();
                  loginBloc.add(const CreateNewWallet());
                },
              )
            else
              LogInOption(
                key: const Key('logInPhraseOrKeyfile'),
                icon: Icon(Icons.key_outlined, size: 20, color: colors.iconMid),
                label: s.logInPhraseOrKeyfile,
                onPressed: () {
                  PlausibleEventTracker.trackClickImportWalletButton();
                  loginBloc.add(const EnterSeedPhrase());
                },
              ),
            if (anyWallet) ...[
              const SizedBox(height: ArDriveSpacing.lg),
              LogInDivider(
                text: signUp ? s.signUpUseYourWallet : s.logInBrowserWallet,
              ),
              const SizedBox(height: ArDriveSpacing.lg),
              if (widget.isArConnectAvailable)
                LogInOption(
                  key: const Key('logInWander'),
                  icon: SvgPicture.asset(
                    Resources.images.login.wanderLogo,
                    width: 20,
                    height: 20,
                  ),
                  label: 'Wander',
                  onPressed: () {
                    PlausibleEventTracker.trackClickContinueWithArconnectButton(
                        pageView);
                    loginBloc.add(const AddWalletFromArConnect());
                  },
                ),
              if (widget.isSolanaAvailable) ...[
                if (widget.isArConnectAvailable)
                  const SizedBox(height: ArDriveSpacing.xs),
                LogInOption(
                  key: const Key('logInSolana'),
                  icon: Image.asset(
                    Resources.images.login.solana,
                    width: 20,
                    height: 20,
                  ),
                  label: s.logInPhantomOrSolflare,
                  onPressed: () {
                    PlausibleEventTracker.trackClickContinueWithSolanaButton(
                        pageView);
                    _connectSolanaWallet(context);
                  },
                ),
              ],
              if (widget.isMetamaskAvailable) ...[
                if (widget.isArConnectAvailable || widget.isSolanaAvailable)
                  const SizedBox(height: ArDriveSpacing.xs),
                LogInOption(
                  key: const Key('logInMetaMask'),
                  icon: SvgPicture.asset(
                    Resources.images.login.metamask,
                    width: 20,
                    height: 20,
                  ),
                  label: 'MetaMask',
                  onPressed: () {
                    PlausibleEventTracker.trackClickContinueWithMetamaskButton(
                        pageView);
                    loginBloc.add(const LoginWithMetamask());
                  },
                ),
              ],
            ],
            const SizedBox(height: ArDriveSpacing.lg),
            if (signUp)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${s.signUpHaveAccount} '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: ArDriveLink(
                        key: const Key('signUpLogIn'),
                        text: s.logIn,
                        isAction: true,
                        style: type.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                        onTap: () {
                          PlausibleEventTracker.trackClickAlreadyHaveAWallet();
                          PlausibleEventTracker.trackPageview(
                              page: PlausiblePageView.loginPage);
                          loginBloc
                              .add(const SelectLoginFlow(existingUser: true));
                        },
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: type.paragraphNormal(color: colors.textLow),
              )
            else
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${s.logInNewToArDrive} '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: ArDriveLink(
                        key: const Key('logInCreateAccount'),
                        text: s.logInCreateAccount,
                        isAction: true,
                        style: type.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                        onTap: () {
                          PlausibleEventTracker.trackClickSignUp();
                          // Sign up's choice: a wallet in the browser is
                          // offered as a new account first.
                          loginBloc.add(const StartSignUp());
                        },
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: type.paragraphNormal(color: colors.textLow),
              ),
          ],
        ),
      ),
    );
  }
}

/// One way to log in: an icon, its name and a chevron, on a full-width
/// secondary button.
@visibleForTesting
class LogInOption extends StatelessWidget {
  const LogInOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    return ArDriveButtonNew(
      text: label,
      typography: type,
      size: ArDriveButtonSize.large,
      maxWidth: double.infinity,
      onPressed: onPressed,
      customContent: Padding(
        // The button's own 10 and these 6 make the design's 16.
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            SizedBox.square(dimension: 20, child: Center(child: icon)),
            const SizedBox(width: ArDriveSpacing.sm),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: type.paragraphLarge(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ),
            ArDriveIcons.carretRight(size: 16, color: colors.iconMid),
          ],
        ),
      ),
    );
  }
}

/// A thin rule each side of a short line of small text.
class LogInDivider extends StatelessWidget {
  const LogInDivider({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final rule = Expanded(child: Container(height: 1, color: colors.strokeLow));
    return LayoutBuilder(
      builder: (context, box) {
        final maxTextWidth = box.maxWidth * 0.8;
        return Row(
          children: [
            rule,
            // Its natural width, up to most of the row: wraps rather than
            // overflows on a narrow panel or a large text size.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxTextWidth),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: ArDriveSpacing.sm),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: type.paragraphSmall(color: colors.textLow),
                ),
              ),
            ),
            rule,
          ],
        );
      },
    );
  }
}

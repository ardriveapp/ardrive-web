import 'dart:ui';

import 'package:ardrive/authentication/components/login_card.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The last step of a new account, in the sign-in panel: save the 12 words
/// that let you sign in on any device. A keyfile is the alternative, for
/// those who want one.
class RecoveryPhraseView extends StatefulWidget {
  const RecoveryPhraseView({
    super.key,
    required this.mnemonic,
    required this.wallet,
    this.saveKeyfile,
  });

  final String mnemonic;
  final Wallet wallet;

  /// Saves the keyfile and says whether it was saved. Replaced in tests.
  final Future<bool> Function(Wallet wallet)? saveKeyfile;

  @override
  State<RecoveryPhraseView> createState() => _RecoveryPhraseViewState();
}

class _RecoveryPhraseViewState extends State<RecoveryPhraseView> {
  bool _shown = false;
  bool _saved = false;

  /// A keyfile was downloaded: the other way to keep the account, so it
  /// also lets them continue. Separate from [_saved], which is about the
  /// phrase.
  bool _keyfileSaved = false;

  @override
  void initState() {
    super.initState();
    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.walletCreatedPage,
    );
  }

  Future<void> _downloadKeyfile() async {
    PlausibleEventTracker.trackClickDownloadKeyfileButton();
    final success = await (widget.saveKeyfile?.call(widget.wallet) ??
        ArDriveIOUtils().downloadWalletAsJsonFile(wallet: widget.wallet));
    if (!success || !mounted) return;
    setState(() => _keyfileSaved = true);
    if (!AppPlatform.isAndroid) return;
    final s = appLocalizationsOf(context);
    showArDriveDialog(
      context,
      content: ArDriveStandardModalNew(
        title: s.recoveryKeyfileDownloaded,
        description: s.recoveryKeyfileDownloadedBody,
        actions: [
          ModalAction(
            title: s.ok,
            action: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final words = widget.mnemonic.split(' ');

    return SizedBox(
      width: 381,
      child: LoginCard(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.recoveryLastStep,
              style: type.paragraphSmall(
                color: colors.textLow,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.recoveryTitle,
              style: type.heading2(
                color: colors.textHigh,
                fontWeight: ArFontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.recoveryBody,
              style: type.paragraphNormal(color: colors.textMid),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.inputDefault,
                border: Border.all(color: colors.strokeMid),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Blurred until asked for, so it is not on screen for
                  // anyone looking over a shoulder.
                  Semantics(
                    label: _shown ? widget.mnemonic : s.recoveryHidden,
                    excludeSemantics: true,
                    child: ImageFiltered(
                      key: const Key('recoveryWords'),
                      enabled: !_shown,
                      imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 3.2,
                        children: [
                          for (final (i, word) in words.indexed)
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: '${i + 1} ',
                                  style: TextStyle(color: colors.textLow),
                                ),
                                TextSpan(text: word),
                              ]),
                              style: type.paragraphNormal(
                                color: colors.textHigh,
                                fontWeight: ArFontWeight.semiBold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    children: [
                      ArDriveLink(
                        key: const Key('recoveryShow'),
                        text: _shown ? s.recoveryHide : s.recoveryShow,
                        isAction: true,
                        onTap: () => setState(() => _shown = !_shown),
                      ),
                      ArDriveLink(
                        text: s.recoveryCopy,
                        isAction: true,
                        onTap: () {
                          PlausibleEventTracker
                              .trackClickCopySeedPhraseButton();
                          Clipboard.setData(
                            ClipboardData(text: widget.mnemonic),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ArDriveCheckBox(
              key: const Key('recoverySaved'),
              checked: _saved,
              // The last two words wrap together, so a phone never leaves
              // one alone on the second line.
              title: _keepLastWordsTogether(s.recoverySaved),
              onChange: (value) {
                PlausibleEventTracker.trackClickBackedUpSeedPhraseCheckBox();
                setState(() => _saved = value);
              },
            ),
            const SizedBox(height: 16),
            ArDriveButtonNew(
              key: const Key('recoveryContinue'),
              size: ArDriveButtonSize.large,
              maxWidth: double.infinity,
              typography: type,
              text: s.recoveryContinue,
              isDisabled: !_saved && !_keyfileSaved,
              variant: ButtonVariant.primary,
              onPressed: () {
                PlausibleEventTracker.trackClickGoToAppButton();
                context
                    .read<LoginBloc>()
                    .add(FinishOnboarding(wallet: widget.wallet));
              },
            ),
            const SizedBox(height: 16),
            Center(
              child: ArDriveLink(
                text: s.recoveryKeyfileInstead,
                isAction: true,
                onTap: _downloadKeyfile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [text] with its last space made non-breaking.
String _keepLastWordsTogether(String text) {
  final last = text.lastIndexOf(' ');
  return last < 0
      ? text
      : '${text.substring(0, last)}\u00A0${text.substring(last + 1)}';
}

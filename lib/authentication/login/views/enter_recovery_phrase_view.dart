import 'package:ardrive/authentication/components/login_card.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/log_in_view.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What is wrong with a recovery phrase as typed.
enum RecoveryPhraseProblem { empty, wordCount, invalid }

/// [raw] as one line of lower-case words with single spaces: how a phrase
/// pasted from a note or typed on a phone that capitalises the first word
/// is meant.
String normaliseRecoveryPhrase(String raw) => raw
    .trim()
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .join(' ');

/// Null when [phrase], normalised, is a recovery phrase. ArDrive makes 12
/// words; the longer BIP39 lengths are kept for phrases made elsewhere.
RecoveryPhraseProblem? checkRecoveryPhrase(String phrase) {
  if (phrase.isEmpty) return RecoveryPhraseProblem.empty;
  final words = phrase.split(' ').length;
  if (!const {12, 15, 18, 21, 24}.contains(words)) {
    return RecoveryPhraseProblem.wordCount;
  }
  if (!bip39.validateMnemonic(phrase)) return RecoveryPhraseProblem.invalid;
  return null;
}

/// Log in with a recovery phrase, or a keyfile instead, in the sign-in
/// panel. The password comes next, in its own step.
///
/// The phrase is a secret: the field is a password field, so it is obscured
/// on screen and to screen readers, never spell-checked, and it is never
/// logged.
class EnterRecoveryPhraseView extends StatefulWidget {
  const EnterRecoveryPhraseView({super.key, this.pickKeyfile});

  /// Opens the file picker. Replaced in tests.
  final Future<IOFile> Function()? pickKeyfile;

  @override
  State<EnterRecoveryPhraseView> createState() =>
      _EnterRecoveryPhraseViewState();
}

class _EnterRecoveryPhraseViewState extends State<EnterRecoveryPhraseView> {
  final _phrase = TextEditingController();
  RecoveryPhraseProblem? _problem;
  bool _keyfileInvalid = false;

  @override
  void initState() {
    super.initState();
    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.importWalletPage,
    );
  }

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  void _submit() {
    final phrase = normaliseRecoveryPhrase(_phrase.text);
    final problem = checkRecoveryPhrase(phrase);
    setState(() {
      _problem = problem;
      _keyfileInvalid = false;
    });
    if (problem != null) return;
    PlausibleEventTracker.trackClickContinueWithSeedphraseButton();
    context.read<LoginBloc>().add(AddWalletFromSeedPhraseLogin(phrase));
  }

  Future<void> _chooseKeyfile() async {
    final loginBloc = context.read<LoginBloc>();
    setState(() {
      _keyfileInvalid = false;
      _problem = null;
    });
    final IOFile file;
    try {
      file = await (widget.pickKeyfile?.call() ??
          ArDriveIO().pickFile(fileSource: FileSource.fileSystem));
    } on ActionCanceledException {
      return;
    } catch (e) {
      logger.w('Could not open the file picker for a keyfile');
      return;
    }
    final wallet = await loginBloc.validateAndReturnWalletFile(file);
    if (!mounted) return;
    if (wallet == null) {
      setState(() => _keyfileInvalid = true);
      return;
    }
    PlausibleEventTracker.trackClickUseKeyfileButton();
    loginBloc.add(AddWalletFile(file));
  }

  String? _problemText(BuildContext context) {
    final s = appLocalizationsOf(context);
    return switch (_problem) {
      RecoveryPhraseProblem.empty => s.phraseEmpty,
      RecoveryPhraseProblem.wordCount => s.phraseWordCount,
      RecoveryPhraseProblem.invalid => s.phraseInvalid,
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final problem = _problemText(context);

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
                key: const Key('phraseBack'),
                text: s.back,
                isAction: true,
                onTap: () => context
                    .read<LoginBloc>()
                    .add(const SelectLoginFlow(existingUser: true)),
              ),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            Text(
              s.phraseTitle,
              style: type.heading2(
                color: colors.textHigh,
                fontWeight: ArFontWeight.bold,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            Text(
              s.phraseBody,
              style: type.paragraphNormal(color: colors.textMid),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            Text(
              s.phraseLabel,
              style: type.paragraphNormal(
                color: colors.textLow,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            ArDriveTextFieldNew(
              key: const Key('recoveryPhraseField'),
              controller: _phrase,
              obscureText: true,
              showObfuscationToggle: true,
              autocorrect: false,
              autofocus: true,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              errorMessage: problem,
              showErrorMessage: problem != null,
              onChanged: (_) {
                if (_problem != null) setState(() => _problem = null);
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            ArDriveButtonNew(
              key: const Key('phraseContinue'),
              size: ArDriveButtonSize.large,
              maxWidth: double.infinity,
              typography: type,
              text: s.phraseContinue,
              variant: ButtonVariant.primary,
              onPressed: _submit,
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            LogInDivider(text: s.phraseOr),
            const SizedBox(height: ArDriveSpacing.lg),
            ArDriveButtonNew(
              key: const Key('phraseChooseKeyfile'),
              size: ArDriveButtonSize.large,
              maxWidth: double.infinity,
              typography: type,
              text: s.phraseChooseKeyfile,
              variant: ButtonVariant.outline,
              icon: ArDriveIcons.file(size: 18, color: colors.iconMid),
              onPressed: _chooseKeyfile,
            ),
            if (_keyfileInvalid) ...[
              const SizedBox(height: ArDriveSpacing.xs),
              ArDriveStatusText(
                key: const Key('keyfileInvalid'),
                text: s.keyfileInvalid,
                type: ArDriveStatusType.error,
              ),
            ],
            const SizedBox(height: ArDriveSpacing.lg),
            Text(
              s.phraseNextPassword,
              textAlign: TextAlign.center,
              style: type.paragraphSmall(color: colors.textLow),
            ),
          ],
        ),
      ),
    );
  }
}

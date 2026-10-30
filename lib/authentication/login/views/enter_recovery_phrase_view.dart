import 'package:ardrive/authentication/components/login_card.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/log_in_view.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/secret_text_field/secret_text_field.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
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

/// The recovery phrase field's text: blurred until shown, and bullets in the
/// semantics tree while it is. iOS and Android screen readers read the
/// bullets. On the web they don't: with semantics on, the engine edits
/// through a real DOM textarea whose value is the plain text, so a web
/// screen reader can read the words, as it could in the old import dialog.
@visibleForTesting
class RecoveryPhraseController extends TextEditingController {
  bool _hidden = true;

  bool get hidden => _hidden;
  set hidden(bool value) {
    _hidden = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!_hidden) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    final color = style?.color ?? Colors.transparent;
    return TextSpan(
      text: text,
      // The words are drawn only as their blurred shadow.
      style: style?.copyWith(
        color: color.withOpacity(0),
        shadows: [Shadow(color: color, blurRadius: 8)],
      ),
      // The semantics value in place of the words. Not on the web, where
      // the DOM textarea underneath holds the plain text.
      semanticsLabel: '\u2022' * text.length,
    );
  }
}

/// Log in with a recovery phrase, or a keyfile instead, in the sign-in
/// panel. The password comes next, in its own step.
///
/// The phrase is a secret, but not a password: a password field would have
/// the browser offer to save the 12 words in its password manager. So it is
/// a plain multi-line field with its words blurred until shown, bullets to
/// iOS and Android screen readers (not web ones, see
/// [RecoveryPhraseController]), and no autocomplete, spell check or
/// suggestions. It is never logged.
class EnterRecoveryPhraseView extends StatefulWidget {
  const EnterRecoveryPhraseView({super.key, this.pickKeyfile});

  /// Opens the file picker. Replaced in tests.
  final Future<IOFile> Function()? pickKeyfile;

  @override
  State<EnterRecoveryPhraseView> createState() =>
      _EnterRecoveryPhraseViewState();
}

class _EnterRecoveryPhraseViewState extends State<EnterRecoveryPhraseView> {
  final _phrase = RecoveryPhraseController();
  final _focus = FocusNode();
  RecoveryPhraseProblem? _problem;
  bool _keyfileInvalid = false;
  bool _keyfileUnreadable = false;

  @override
  void initState() {
    super.initState();
    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.importWalletPage,
    );
    _focus.addListener(_markSecret);
  }

  @override
  void dispose() {
    _phrase.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _markSecret() {
    if (!_focus.hasFocus) return;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => markFocusedFieldSecret());
  }

  void _submit() {
    final phrase = normaliseRecoveryPhrase(_phrase.text);
    final problem = checkRecoveryPhrase(phrase);
    setState(() {
      _problem = problem;
      _keyfileInvalid = false;
      _keyfileUnreadable = false;
    });
    if (problem != null) return;
    PlausibleEventTracker.trackClickContinueWithSeedphraseButton();
    context.read<LoginBloc>().add(AddWalletFromSeedPhraseLogin(phrase));
  }

  Future<void> _chooseKeyfile() async {
    final loginBloc = context.read<LoginBloc>();
    setState(() {
      _keyfileInvalid = false;
      _keyfileUnreadable = false;
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
    final Wallet? wallet;
    try {
      wallet = await loginBloc.validateAndReturnWalletFile(file);
    } on KeyfileUnreadableException {
      if (mounted) setState(() => _keyfileUnreadable = true);
      return;
    }
    if (!mounted) return;
    if (wallet == null) {
      setState(() => _keyfileInvalid = true);
      return;
    }
    PlausibleEventTracker.trackClickUseKeyfileButton();
    // The wallet, not the file: the file isn't read a second time.
    loginBloc.add(AddWalletFile(wallet));
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
              focusNode: _focus,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              minLines: 3,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.done,
              errorMessage: problem,
              showErrorMessage: problem != null,
              onChanged: (_) {
                markFocusedFieldSecret();
                if (_problem != null) setState(() => _problem = null);
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: ArDriveLink(
                key: const Key('phraseShow'),
                text: _phrase.hidden ? s.recoveryShow : s.recoveryHide,
                isAction: true,
                onTap: () => setState(() => _phrase.hidden = !_phrase.hidden),
              ),
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
              // A keyfile is a JSON file.
              icon: ArDriveIcons.json(size: 18, color: colors.iconMid),
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
            if (_keyfileUnreadable) ...[
              const SizedBox(height: ArDriveSpacing.xs),
              ArDriveStatusText(
                key: const Key('keyfileUnreadable'),
                text: s.keyfileUnreadable,
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

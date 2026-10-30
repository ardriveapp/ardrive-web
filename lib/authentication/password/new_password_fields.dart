import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:ardrive/authentication/password/new_password.dart';
import 'package:ardrive/components/password_autofill.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Setting a new password under the new-account rules: at least 12
/// characters, strong, not in a known breach, with a suggested passphrase on
/// offer, typed twice.
///
/// Both fields are `new-password` for the browser, in one autofill group
/// with a hidden username ([username], the wallet address), so a password
/// manager offers to save it for this account. Call
/// [PasswordAutofillGroup.save] once it has been used.
///
/// Read the password with [NewPasswordFieldsState.confirmedPassword], which
/// runs the breach check: a typed password goes out (as a 5-character hash
/// prefix) only then, not on every keystroke.
class NewPasswordFields extends StatefulWidget {
  const NewPasswordFields({
    super.key,
    required this.username,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.breachCheck,
    this.autofocus = true,
  });

  final String username;
  final bool enabled;

  /// Told whenever the fields become usable or stop being so.
  final ValueChanged<bool>? onChanged;

  /// Enter in the confirm field, when the fields are usable.
  final VoidCallback? onSubmitted;

  /// Asks whether a typed password is in a known breach. Replaced in tests.
  final BreachedPasswordCheck? breachCheck;
  final bool autofocus;

  @override
  State<NewPasswordFields> createState() => NewPasswordFieldsState();
}

class NewPasswordFieldsState extends State<NewPasswordFields> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// The passphrase last suggested, while it is what the field holds.
  String? _suggestion;

  /// A password the breach check found, so the field says so until changed.
  String? _breached;
  bool _confirmTouched = false;

  PasswordStrength? get _strength =>
      _password.text.isEmpty ? null : assessNewPassword(_password.text);

  bool get _strong => _strength == PasswordStrength.strong;

  bool get _matches =>
      _confirm.text.isNotEmpty && _confirm.text == _password.text;

  /// Whether the password may be used, as far as can be told without the
  /// breach check.
  bool get isValid => _strong && _matches && _password.text != _breached;

  bool _lastValid = false;

  void _changed() {
    setState(() {
      if (_password.text != _suggestion) _suggestion = null;
    });
    final valid = isValid;
    if (valid != _lastValid) {
      _lastValid = valid;
      widget.onChanged?.call(valid);
    }
  }

  Future<void> _suggest() async {
    final words = await loadPassphraseWords(DefaultAssetBundle.of(context));
    if (!mounted) return;
    final phrase = suggestPassphrase(words);
    _password.text = phrase;
    _confirm.text = phrase;
    _suggestion = phrase;
    _confirmTouched = true;
    _changed();
  }

  /// The password, once it passes the breach check; null, with the field
  /// saying why, when it doesn't. A suggestion is random and never checked.
  /// The service being away lets it through.
  Future<String?> confirmedPassword() async {
    if (!isValid) return null;
    final password = _password.text;
    if (password != _suggestion) {
      final breached = await (widget.breachCheck ?? BreachedPasswordCheck())
          .isBreached(password);
      if (!mounted) return null;
      if (breached == true) {
        _breached = password;
        _changed();
        return null;
      }
    }
    return password;
  }

  String? _passwordError(BuildContext context) {
    final s = appLocalizationsOf(context);
    if (_password.text.isNotEmpty && _password.text == _breached) {
      return s.newPasswordBreached;
    }
    return switch (_strength) {
      null || PasswordStrength.strong => null,
      PasswordStrength.tooShort => s.newPasswordTooShort,
      PasswordStrength.weak => s.newPasswordWeak,
      PasswordStrength.fair => s.newPasswordFair,
    };
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final passwordError = _passwordError(context);
    final confirmError = _confirmTouched &&
            _confirm.text.isNotEmpty &&
            _confirm.text != _password.text
        ? s.passwordMismatch
        : null;
    final strength = _strength;

    return PasswordAutofillGroup(
      username: widget.username,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.password,
            style: type.paragraphNormal(
              color: colors.textLow,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: 8),
          ArDriveTextFieldNew(
            key: const Key('newPassword'),
            controller: _password,
            hintText: s.newPasswordHint,
            obscureText: true,
            showObfuscationToggle: true,
            autofocus: widget.autofocus,
            autocorrect: false,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            isEnabled: widget.enabled,
            errorMessage: passwordError,
            showErrorMessage: passwordError != null,
            onChanged: (_) => _changed(),
          ),
          if (strength != null) ...[
            const SizedBox(height: 8),
            PasswordStrengthMeter(strength: strength),
          ],
          const SizedBox(height: 12),
          if (_suggestion == null)
            Align(
              alignment: Alignment.centerLeft,
              child: ArDriveButtonNew(
                key: const Key('suggestPasswordButton'),
                size: ArDriveButtonSize.compact,
                text: s.newPasswordSuggest,
                typography: type,
                variant: ButtonVariant.secondary,
                isDisabled: !widget.enabled,
                onPressed: _suggest,
              ),
            )
          else
            SuggestedPassphrase(
              phrase: _suggestion!,
              onAnother: widget.enabled ? _suggest : null,
            ),
          const SizedBox(height: 20),
          Text(
            s.confirmPassword,
            style: type.paragraphNormal(
              color: colors.textLow,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: 8),
          ArDriveTextFieldNew(
            key: const Key('confirmNewPassword'),
            controller: _confirm,
            hintText: s.confirmPasswordHint,
            obscureText: true,
            showObfuscationToggle: true,
            autocorrect: false,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            isEnabled: widget.enabled,
            errorMessage: confirmError,
            showErrorMessage: confirmError != null,
            onChanged: (_) {
              _confirmTouched = true;
              _changed();
            },
            onFieldSubmitted: (_) {
              if (isValid) widget.onSubmitted?.call();
            },
          ),
        ],
      ),
    );
  }
}

/// Four bars and a word: how strong a new password looks.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.strength});

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
class SuggestedPassphrase extends StatelessWidget {
  const SuggestedPassphrase({
    super.key,
    required this.phrase,
    required this.onAnother,
  });

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

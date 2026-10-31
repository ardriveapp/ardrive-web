import 'dart:async';

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

  /// Whether both fields hide what they hold. One eye, on the password
  /// field, controls both, and only it: a suggestion fills both fields
  /// masked, as a phone's screen may be seen or recorded.
  bool _obscured = true;

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
      if (_suggestion != null && _password.text != _suggestion) {
        _suggestion = null;
      }
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
    // The caret after it, not the whole of it selected.
    final filled = TextEditingValue(
      text: phrase,
      selection: TextSelection.collapsed(offset: phrase.length),
    );
    _password.value = filled;
    _confirm.value = filled;
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
          const SizedBox(height: ArDriveSpacing.xs),
          ArDriveTextFieldNew(
            key: const Key('newPassword'),
            controller: _password,
            hintText: s.newPasswordHint,
            obscureText: _obscured,
            suffixIcon: PasswordRevealToggle(
              key: const Key('newPasswordReveal'),
              obscured: _obscured,
              onToggle: () => setState(() => _obscured = !_obscured),
            ),
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
            const SizedBox(height: ArDriveSpacing.xs),
            PasswordStrengthMeter(strength: strength),
          ],
          const SizedBox(height: ArDriveSpacing.sm),
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
          const SizedBox(height: ArDriveSpacing.md),
          Text(
            s.confirmPassword,
            style: type.paragraphNormal(
              color: colors.textLow,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: ArDriveSpacing.xs),
          ArDriveTextFieldNew(
            key: const Key('confirmNewPassword'),
            controller: _confirm,
            hintText: s.confirmPasswordHint,
            obscureText: _obscured,
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

/// Under a suggested passphrase, which the fields hold masked: Copy, and
/// another suggestion. It is made on the device and kept nowhere; saving it
/// is up to the user.
///
/// Copy says whether it worked, at the end of the row as the meter above
/// says "Strong": a phone's browser can refuse the write, and saying
/// "Copied!" anyway would leave someone thinking a password they never saved
/// is safe. It is in the row, not an overlay: a bubble placed once covered
/// the meter and stayed put when the modal scrolled.
class SuggestedPassphrase extends StatefulWidget {
  const SuggestedPassphrase({
    super.key,
    required this.phrase,
    required this.onAnother,
  });

  final String phrase;
  final VoidCallback? onAnother;

  @override
  State<SuggestedPassphrase> createState() => _SuggestedPassphraseState();
}

class _SuggestedPassphraseState extends State<SuggestedPassphrase> {
  static const _shownFor = Duration(seconds: 2);
  static const _fade = Duration(milliseconds: 200);

  /// Whether the last copy worked, while its message is in the row.
  bool? _copied;

  /// Whether that message is showing, rather than fading out.
  bool _showing = false;
  Timer? _hide;

  /// Bumped when the phrase changes, so a copy of the last one that answers
  /// late, or its message still up, never speaks for the new one.
  int _revision = 0;

  @override
  void didUpdateWidget(covariant SuggestedPassphrase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phrase != widget.phrase) {
      _revision++;
      _hide?.cancel();
      _copied = null;
      _showing = false;
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    // Asked for at once, inside the tap: a browser refuses a write that comes
    // later. Then waited on, because it can refuse this one too.
    final revision = _revision;
    final write = Clipboard.setData(ClipboardData(text: widget.phrase));

    bool copied;
    try {
      await write;
      copied = true;
    } catch (_) {
      copied = false;
    }
    if (!mounted || revision != _revision) return;

    // A retry while the last answer shows says the new one, for its own two
    // seconds.
    setState(() {
      _copied = copied;
      _showing = true;
    });
    _hide?.cancel();
    _hide = Timer(_shownFor, () {
      if (mounted) setState(() => _showing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final copied = _copied;
    // A row like the meter's above: the links on the left, wrapping at large
    // text sizes, and the copy's answer at the end, as "Strong" is there.
    return Row(
      key: const Key('suggestedPassphrase'),
      children: [
        Expanded(
          child: Wrap(
            spacing: ArDriveSpacing.md,
            runSpacing: ArDriveSpacing.xs,
            children: [
              ArDriveLink(
                text: s.newPasswordCopy,
                isAction: true,
                onTap: _copy,
              ),
              if (widget.onAnother != null)
                ArDriveLink(
                  text: s.newPasswordSuggestAnother,
                  isAction: true,
                  onTap: widget.onAnother!,
                ),
            ],
          ),
        ),
        if (copied != null) ...[
          const SizedBox(width: ArDriveSpacing.sm),
          AnimatedOpacity(
            key: const Key('suggestedPassphraseCopyMessage'),
            opacity: _showing ? 1 : 0,
            duration: _fade,
            // Gone once faded, so it is not read out or found again.
            onEnd: () {
              if (!_showing && mounted) setState(() => _copied = null);
            },
            child: Semantics(
              liveRegion: true,
              child: Text(
                copied ? s.copied : s.couldNotCopy,
                style: type.paragraphSmall(
                  color: copied ? colors.statusSuccessFg : colors.statusErrorFg,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The one eye of a new password and its confirmation: shows or hides both.
class PasswordRevealToggle extends StatelessWidget {
  const PasswordRevealToggle({
    super.key,
    required this.obscured,
    required this.onToggle,
  });

  final bool obscured;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final s = appLocalizationsOf(context);
    return Semantics(
      button: true,
      label: obscured ? s.showPassword : s.hidePassword,
      child: GestureDetector(
        onTap: onToggle,
        child: ArDriveClickArea(
          child: ArDriveIcon(
            size: 20,
            icon: obscured
                ? ArDriveIconsData.eye_closed
                : ArDriveIconsData.eye_open,
            color: obscured ? colors.iconLow : colors.iconMid,
          ),
        ),
      ),
    );
  }
}

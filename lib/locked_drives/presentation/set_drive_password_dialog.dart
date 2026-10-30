import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:ardrive/authentication/password/new_password_fields.dart';
import 'package:ardrive/components/password_autofill.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// "Keep your files private": asks someone who signed in with a browser
/// wallet, and so has no drive password yet, to set one before their first
/// private drive is made. Returns the password, or null for Cancel.
///
/// The new-account rules apply (see [NewPasswordFields]). Nothing is made
/// here: the caller makes the drive with what this returns, and on Cancel
/// makes nothing.
Future<String?> showSetDrivePasswordDialog(
  BuildContext context, {
  required String walletAddress,
  BreachedPasswordCheck? breachCheck,
}) {
  return showArDriveDialogWithBuilder<String>(
    context,
    barrierDismissible: false,
    builder: (_) => SetDrivePasswordDialog(
      walletAddress: walletAddress,
      breachCheck: breachCheck,
    ),
  );
}

class SetDrivePasswordDialog extends StatefulWidget {
  const SetDrivePasswordDialog({
    super.key,
    required this.walletAddress,
    this.breachCheck,
  });

  final String walletAddress;
  final BreachedPasswordCheck? breachCheck;

  @override
  State<SetDrivePasswordDialog> createState() => _SetDrivePasswordDialogState();
}

class _SetDrivePasswordDialogState extends State<SetDrivePasswordDialog> {
  final _fields = GlobalKey<NewPasswordFieldsState>();
  bool _valid = false;
  bool _checking = false;

  Future<void> _submit() async {
    final fields = _fields.currentState;
    if (fields == null || !_valid || _checking) return;
    setState(() => _checking = true);
    final password = await fields.confirmedPassword();
    if (!mounted) return;
    setState(() => _checking = false);
    if (password == null) return;
    PasswordAutofillGroup.save();
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final type = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;

    return ArDriveStandardModalNew(
      key: const Key('setDrivePasswordDialog'),
      title: s.setDrivePasswordTitle,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.setDrivePasswordBody,
              style: type.paragraphNormal(color: colors.textMid),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            NewPasswordFields(
              key: _fields,
              username: widget.walletAddress,
              enabled: !_checking,
              breachCheck: widget.breachCheck,
              onChanged: (valid) => setState(() => _valid = valid),
              onSubmitted: _submit,
            ),
          ],
        ),
      ),
      actions: [
        ModalAction.dismiss(
          action: () => Navigator.of(context).pop(),
          title: s.cancelEmphasized,
        ),
        ModalAction(
          action: _submit,
          title: s.setDrivePasswordAction,
          isEnable: _valid,
          isLoading: _checking,
        ),
      ],
    );
  }
}

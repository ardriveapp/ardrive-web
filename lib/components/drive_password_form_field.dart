import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class DrivePasswordFormField extends StatefulWidget {
  final Function(String?) onPasswordChanged;
  final bool isVisible;

  const DrivePasswordFormField({
    super.key,
    required this.onPasswordChanged,
    required this.isVisible,
  });

  @override
  State<DrivePasswordFormField> createState() => _DrivePasswordFormFieldState();
}

class _DrivePasswordFormFieldState extends State<DrivePasswordFormField> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _validatePasswords() {
    setState(() {
      _passwordError = null;
      _confirmPasswordError = null;

      final password = _passwordController.text;
      final confirmPassword = _confirmPasswordController.text;

      if (password.isEmpty) {
        _passwordError = 'Password is required';
        widget.onPasswordChanged(null);
        return;
      }

      if (confirmPassword.isEmpty) {
        _confirmPasswordError = 'Please confirm your password';
        widget.onPasswordChanged(null);
        return;
      }

      if (password != confirmPassword) {
        _confirmPasswordError = 'Passwords do not match';
        widget.onPasswordChanged(null);
        return;
      }

      // Passwords are valid
      widget.onPasswordChanged(password);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      return const SizedBox.shrink();
    }

    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorTokens.containerL2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorTokens.strokeLow,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: colorTokens.textRed,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Set Your Drive Password',
                    style: typography.paragraphLarge(
                      fontWeight: ArFontWeight.bold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Each private drive has its own password for enhanced security. '
                'This password cannot be recovered or reset by anyone, including ArDrive. '
                'Please store it securely - you will need it to access this drive.',
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
              const SizedBox(height: 16),

              // Password field
              ArDriveTextFieldNew(
                controller: _passwordController,
                obscureText: true,
                showObfuscationToggle: true,
                hintText: 'Enter drive password',
                label: 'Drive Password',
                onChanged: (_) => _validatePasswords(),
                errorMessage: _passwordError,
              ),
              const SizedBox(height: 16),

              // Confirm password field
              ArDriveTextFieldNew(
                controller: _confirmPasswordController,
                obscureText: true,
                showObfuscationToggle: true,
                hintText: 'Confirm drive password',
                label: 'Confirm Password',
                onChanged: (_) => _validatePasswords(),
                errorMessage: _confirmPasswordError,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

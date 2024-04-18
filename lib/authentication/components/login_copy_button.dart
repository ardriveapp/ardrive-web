import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LoginCopyButton extends StatefulWidget {
  final String text;
  final double size;
  final bool showCopyText;
  final Widget? child;
  final int positionY;
  final int positionX;
  final Color? copyMessageColor;

  const LoginCopyButton({
    super.key,
    required this.text,
    this.size = 20,
    this.showCopyText = true,
    this.child,
    this.positionY = 40,
    this.positionX = 20,
    this.copyMessageColor,
  });

  @override
  // ignore: library_private_types_in_public_api
  _LoginCopyButtonState createState() => _LoginCopyButtonState();
}

class _LoginCopyButtonState extends State<LoginCopyButton> {
  bool _showCheck = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: TextButton.icon(
          icon: _showCheck
              ? ArDriveIcons.checkCirle(
                  size: 24,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeSuccessDefault,
                )
              : ArDriveIcons.copy(
                  size: 24,
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgMuted),
          label: Text(
            // TODO: create/update localization keys
            _showCheck ? 'Copied to Clipboard' : 'Copy to Clipboard',
            style: ArDriveTypography.body.smallBold(
                color: ArDriveTheme.of(context).themeData.colors.themeFgMuted),
          ),
          onPressed: _copy,
        ));
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    if (mounted) {
      if (_showCheck) {
        return;
      }

      setState(() {
        _showCheck = true;

        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) {
            return;
          }

          setState(() {
            _showCheck = false;
          });
        });
      });
    }
  }
}

// ignore_for_file: deprecated_member_use

import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';

void showErrorDialog(
    {required BuildContext context,
    String? title,
    required String message,
    bool showShareLogsButton = false}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final typography = ArDriveTypographyNew.of(context);

  showArDriveDialog(
    context,
    barrierDismissible: false,
    useRootNavigator: false,
    content: ArDriveLoginModal(
      width: 440,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
              child: SvgPicture.asset(
            Resources.images.icons.alert,
            color: colorTokens.strokeRed,
            height: 48,
          )),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.topCenter,
            child: Text(
              title ?? appLocalizationsOf(context).error,
              style: typography.heading2(
                  color: colorTokens.textHigh, fontWeight: ArFontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: typography.paragraphNormal(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold)),
          const SizedBox(height: 40),
          SizedBox(
            width: 440,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ArDriveButtonNew(
                    text: 'Close',
                    typography: typography,
                    variant: ButtonVariant.secondary,
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ),
                if (showShareLogsButton) const SizedBox(width: 12),
                if (showShareLogsButton)
                  const Flexible(
                    child: CopyLogsButton(),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class CopyLogsButton extends StatefulWidget {
  const CopyLogsButton({super.key});

  @override
  State<CopyLogsButton> createState() => _CopyLogsButtonState();
}

class _CopyLogsButtonState extends State<CopyLogsButton> {
  bool copied = false;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveButtonNew(
      text: copied ? 'Copied' : 'Copy Logs',
      typography: typography,
      variant: ButtonVariant.primary,
      onPressed: () async {
        final logs = await logger.getLogs();
        Clipboard.setData(ClipboardData(text: logs));
        setState(() {
          copied = true;
        });
      },
    );
  }
}

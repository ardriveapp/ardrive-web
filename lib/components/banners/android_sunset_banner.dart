import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class AndroidSunsetBanner extends StatelessWidget {
  const AndroidSunsetBanner({
    super.key,
    required this.onDismiss,
  });

  static const _learnMoreUrl = 'https://ardrive.io/mobile';

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    final colors = theme.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.themeWarningSubtle,
        border: Border(
          bottom: BorderSide(
            color: colors.themeWarningEmphasis,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ArDriveIcons.info(
                  size: 20,
                  color: colors.themeWarningEmphasis,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: typography.paragraphNormal(
                        color: colors.themeWarningEmphasis,
                        fontWeight: ArFontWeight.semiBold,
                      ),
                      children: [
                        const TextSpan(
                          text:
                              'The ArDrive Android app is being sunset. Make sure to back up any wallets generated in the Android app. ',
                        ),
                        TextSpan(
                          text: 'Learn more',
                          style: typography
                              .paragraphNormal(
                                color: colors.themeWarningEmphasis,
                                fontWeight: ArFontWeight.semiBold,
                              )
                              .copyWith(
                                decoration: TextDecoration.underline,
                              ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => openUrl(
                                  url: _learnMoreUrl,
                                  webOnlyWindowName: '_blank',
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            label: 'Dismiss',
            button: true,
            child: IconButton(
              iconSize: 20,
              splashRadius: 20,
              onPressed: onDismiss,
              icon: Icon(
                Icons.close,
                size: 20,
                color: colors.themeWarningEmphasis,
              ),
              tooltip: 'Dismiss',
            ),
          ),
        ],
      ),
    );
  }
}

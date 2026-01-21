import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class AppAnnouncementBanner extends StatelessWidget {
  const AppAnnouncementBanner({
    super.key,
    required this.message,
    required this.onDismiss,
    this.url,
    this.urlText,
  });

  final String message;
  final VoidCallback onDismiss;
  final String? url;
  final String? urlText;

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
                        TextSpan(text: message),
                        if (url != null) ...[
                          const TextSpan(text: ' '),
                          TextSpan(
                            text: urlText ?? 'Learn more',
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
                                    url: url!,
                                    webOnlyWindowName: '_blank',
                                  ),
                          ),
                        ],
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

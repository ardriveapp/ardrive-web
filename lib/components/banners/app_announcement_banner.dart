import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// An announcement across the top of the app: the standard banner notice,
/// with "Learn more" when there's a link and a close button.
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
    final url = this.url;

    return ArDriveNotice(
      type: ArDriveNoticeType.info,
      layout: ArDriveNoticeLayout.banner,
      message: message,
      actionLabel: url != null ? urlText ?? 'Learn more' : null,
      onAction: url != null
          ? () => openUrl(url: url, webOnlyWindowName: '_blank')
          : null,
      onDismiss: onDismiss,
    );
  }
}

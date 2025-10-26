// Stub implementation for non-web platforms
// ignore_for_file: avoid_classes_with_only_static_members

import 'package:ardrive/services/eml_parser/models/email_attachment.dart';
import 'package:flutter/material.dart';

/// Web-specific audio preview - not available on this platform
void showAudioPreview(
  BuildContext context,
  EmailAttachment attachment,
  dynamic colors,
  dynamic typography,
) {
  throw UnsupportedError('Audio preview is only available on web platform');
}

/// Web-specific video preview - not available on this platform
void showVideoPreview(
  BuildContext context,
  EmailAttachment attachment,
) {
  throw UnsupportedError('Video preview is only available on web platform');
}

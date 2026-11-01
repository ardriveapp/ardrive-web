// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:ardrive/pages/drive_detail/components/email_attachment_preview_dialog.dart';
import 'package:ardrive/services/eml_parser/models/email_attachment.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Web-specific implementation of audio preview
void showAudioPreview(BuildContext context, EmailAttachment attachment) {
  if (attachment.data == null) return;

  // Create a blob URL from the attachment
  final blob = html.Blob([attachment.data!], attachment.mimeType);
  final blobUrl = html.Url.createObjectUrlFromBlob(blob);

  // Use unique viewType to avoid registration conflicts on repeated previews
  final viewType =
      'audio-preview-${attachment.id}-${DateTime.now().microsecondsSinceEpoch}';

  try {
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final audioElement = html.AudioElement()
        ..src = blobUrl
        ..controls = true
        ..style.width = '100%'
        ..autoplay = true;
      return audioElement;
    });
  } catch (e) {
    // Log error and notify user
    logger.e('Failed to register audio preview view factory', e);

    _showPreviewFailed(context);

    // Clean up blob URL
    html.Url.revokeObjectUrl(blobUrl);
    return;
  }

  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  showEmailAttachmentDialog(
    context,
    attachment: attachment,
    width: 600,
    content: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArDriveIcons.music(size: 64, color: colorTokens.iconLow),
          const SizedBox(height: ArDriveSpacing.md),
          // HTML5 audio player
          SizedBox(
            width: 300,
            height: 54,
            child: HtmlElementView(viewType: viewType),
          ),
        ],
      ),
    ),
  ).then((_) {
    // Cleanup blob URL when dialog closes
    html.Url.revokeObjectUrl(blobUrl);
  });
}

/// Web-specific implementation of video preview
void showVideoPreview(
  BuildContext context,
  EmailAttachment attachment,
) {
  if (attachment.data == null) return;

  // Create a blob URL from the attachment
  final blob = html.Blob([attachment.data!], attachment.mimeType);
  final blobUrl = html.Url.createObjectUrlFromBlob(blob);

  // Use unique viewType to avoid registration conflicts on repeated previews
  final viewType =
      'video-preview-${attachment.id}-${DateTime.now().microsecondsSinceEpoch}';

  try {
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final videoElement = html.VideoElement()
        ..src = blobUrl
        ..controls = true
        ..style.maxWidth = '100%'
        ..style.maxHeight = '100%'
        ..autoplay = true;
      return videoElement;
    });
  } catch (e) {
    // Log error and notify user
    logger.e('Failed to register video preview view factory', e);

    _showPreviewFailed(context);

    // Clean up blob URL
    html.Url.revokeObjectUrl(blobUrl);
    return;
  }

  showEmailAttachmentDialog(
    context,
    attachment: attachment,
    content: SizedBox(
      width: double.infinity,
      height: 500,
      child: HtmlElementView(viewType: viewType),
    ),
  ).then((_) {
    // Cleanup blob URL when dialog closes
    html.Url.revokeObjectUrl(blobUrl);
  });
}

/// Said when the browser could not set up an attachment's player.
void _showPreviewFailed(BuildContext context) {

  showArDriveToast(
    ScaffoldMessenger.of(context),
    text: appLocalizationsOf(context).emailAttachmentPreviewFailed,
    type: ArDriveStatusType.error,
    duration: const Duration(seconds: 3),
  );
}

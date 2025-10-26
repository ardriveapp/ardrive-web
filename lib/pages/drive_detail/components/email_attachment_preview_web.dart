// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:ardrive/services/eml_parser/models/email_attachment.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Web-specific implementation of audio preview
void showAudioPreview(
  BuildContext context,
  EmailAttachment attachment,
  dynamic colors,
  dynamic typography,
) {
  if (attachment.data == null) return;

  // Create a blob URL from the attachment
  final blob = html.Blob([attachment.data!], attachment.mimeType);
  final blobUrl = html.Url.createObjectUrlFromBlob(blob);

  // Use unique viewType to avoid registration conflicts on repeated previews
  final viewType = 'audio-preview-${attachment.id}-${DateTime.now().microsecondsSinceEpoch}';

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
    // View factory already registered, clean up and return
    html.Url.revokeObjectUrl(blobUrl);
    return;
  }

  showDialog(
    context: context,
    builder: (context) => Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPreviewHeader(context, attachment),
            // Audio player
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArDriveIcons.music(size: 64, color: colors.themeFgDefault),
                    const SizedBox(height: 16),
                    Text(
                      attachment.filename,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // HTML5 audio player
                    SizedBox(
                      width: 300,
                      height: 54,
                      child: HtmlElementView(viewType: viewType),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
  final viewType = 'video-preview-${attachment.id}-${DateTime.now().microsecondsSinceEpoch}';

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
    // View factory already registered, clean up and return
    html.Url.revokeObjectUrl(blobUrl);
    return;
  }

  showDialog(
    context: context,
    builder: (context) => Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPreviewHeader(context, attachment),
            // Video player
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: 500,
                    child: HtmlElementView(viewType: viewType),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ).then((_) {
    // Cleanup blob URL when dialog closes
    html.Url.revokeObjectUrl(blobUrl);
  });
}

Widget _buildPreviewHeader(BuildContext context, EmailAttachment attachment) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
      border: Border(
        bottom: BorderSide(
          color: ArDriveTheme.of(context).themeData.colors.themeBorderDefault,
        ),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            attachment.filename,
            style: ArDriveTypography.body.smallBold700(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

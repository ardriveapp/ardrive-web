// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;

import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/eml_parser/models/email_attachment.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class EmailAttachmentList extends StatelessWidget {
  final List<EmailAttachment> attachments;

  const EmailAttachmentList({
    super.key,
    required this.attachments,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ArDriveIcons.file(size: 16, color: colors.themeFgDefault),
              const SizedBox(width: 8),
              Text(
                'Attachments (${attachments.length})',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...attachments.map((attachment) => _buildAttachmentItem(
                context,
                attachment,
                colors,
                typography,
              )),
        ],
      ),
    );
  }

  Widget _buildAttachmentItem(
    BuildContext context,
    EmailAttachment attachment,
    dynamic colors,
    dynamic typography,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.themeBgCanvas,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.themeBorderDefault, width: 1),
      ),
      child: Row(
        children: [
          // File icon
          _getFileIcon(attachment, colors),
          const SizedBox(width: 12),
          // File info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.filename,
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${attachment.sizeFormatted} • ${attachment.mimeType}',
                  style: typography.caption(
                    color: colors.themeFgMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachment.isPreviewable && attachment.data != null)
                ArDriveIconButton(
                  icon: ArDriveIcons.eyeOpen(size: 20),
                  tooltip: 'Preview',
                  onPressed: () => _previewAttachment(context, attachment),
                ),
              if (attachment.isPreviewable && attachment.data != null)
                const SizedBox(width: 8),
              ArDriveIconButton(
                icon: ArDriveIcons.download(size: 20),
                tooltip: 'Download',
                onPressed: () => _downloadAttachment(attachment),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _getFileIcon(EmailAttachment attachment, dynamic colors) {
    if (attachment.isImage) {
      return ArDriveIcons.image(size: 24, color: colors.themeFgDefault);
    } else if (attachment.isPdf) {
      return ArDriveIcons.fileOutlined(size: 24, color: colors.themeFgDefault);
    } else {
      return ArDriveIcons.file(size: 24, color: colors.themeFgDefault);
    }
  }

  Future<void> _downloadAttachment(EmailAttachment attachment) async {
    if (attachment.data == null) {
      return;
    }

    final ioFile = await IOFile.fromData(
      attachment.data!,
      name: attachment.filename,
      lastModifiedDate: DateTime.now(),
      contentType: attachment.contentType,
    );

    await ArDriveIO().saveFile(ioFile);
  }

  void _previewAttachment(BuildContext context, EmailAttachment attachment) {
    if (attachment.data == null) return;

    if (attachment.isImage) {
      _previewImage(context, attachment);
    } else if (attachment.isTextFile) {
      _previewText(context, attachment);
    } else if (attachment.isAudio) {
      _previewAudio(context, attachment);
    } else if (attachment.isVideo) {
      _previewVideo(context, attachment);
    }
  }

  void _previewImage(BuildContext context, EmailAttachment attachment) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPreviewHeader(context, attachment),
              // Image
              Flexible(
                child: Center(
                  child: Image.memory(
                    attachment.data!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _previewText(BuildContext context, EmailAttachment attachment) {
    if (attachment.data == null) return;

    String textContent;
    try {
      textContent = utf8.decode(attachment.data!, allowMalformed: true);
    } catch (e) {
      // If UTF-8 decoding fails, show error
      textContent = 'Error: Unable to decode text content. File may be corrupted or in an unsupported encoding.';
    }

    // Limit text preview to avoid performance issues with very large files
    const maxPreviewLength = 1024 * 1024; // 1MB of text
    if (textContent.length > maxPreviewLength) {
      textContent = '${textContent.substring(0, maxPreviewLength)}\n\n... (File truncated. Download to view full content)';
    }

    final typography = ArDriveTypographyNew.of(context);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPreviewHeader(context, attachment),
              // Text content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    textContent,
                    style: typography.paragraphSmall().copyWith(
                      fontFamily: 'Courier New',
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _previewAudio(BuildContext context, EmailAttachment attachment) {
    if (attachment.data == null) return;

    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    // Create a blob URL from the attachment
    final blob = html.Blob([attachment.data!], attachment.mimeType);
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);

    // Use unique viewType to avoid registration conflicts on repeated previews
    final viewType = 'audio-preview-${attachment.id}-${math.Random().nextInt(999999)}';

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

  void _previewVideo(BuildContext context, EmailAttachment attachment) {
    if (attachment.data == null) return;

    // Create a blob URL from the attachment
    final blob = html.Blob([attachment.data!], attachment.mimeType);
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);

    // Use unique viewType to avoid registration conflicts on repeated previews
    final viewType = 'video-preview-${attachment.id}-${math.Random().nextInt(999999)}';

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
}

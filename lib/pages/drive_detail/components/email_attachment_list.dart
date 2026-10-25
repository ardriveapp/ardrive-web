import 'dart:convert';

import 'package:ardrive/pages/drive_detail/components/email_attachment_preview_dialog.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/eml_parser/models/email_attachment.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

import 'email_attachment_preview_stub.dart'
    if (dart.library.html) 'email_attachment_preview_web.dart';

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

    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      margin: const EdgeInsets.only(top: ArDriveSpacing.md),
      padding: const EdgeInsets.all(ArDriveSpacing.md),
      decoration: BoxDecoration(
        color: colorTokens.containerL2,
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ArDriveIcons.file(size: 16, color: colorTokens.iconMid),
              const SizedBox(width: ArDriveSpacing.xs),
              Text(
                appLocalizationsOf(context)
                    .emailAttachments(attachments.length),
                style: typography.paragraphNormal(
                  color: colorTokens.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ],
          ),
          const SizedBox(height: ArDriveSpacing.sm),
          ...attachments.map((attachment) => _buildAttachmentItem(
                context,
                attachment,
                colorTokens,
                typography,
              )),
        ],
      ),
    );
  }

  Widget _buildAttachmentItem(
    BuildContext context,
    EmailAttachment attachment,
    ArDriveColorTokens colorTokens,
    ArdriveTypographyNew typography,
  ) {
    final l10n = appLocalizationsOf(context);

    return Container(
      margin: const EdgeInsets.only(bottom: ArDriveSpacing.xs),
      padding: const EdgeInsets.all(ArDriveSpacing.sm),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Row(
        children: [
          _getFileIcon(attachment, colorTokens),
          const SizedBox(width: ArDriveSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.filename,
                  style: typography.paragraphSmall(
                    color: colorTokens.textHigh,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: ArDriveSpacing.xxs),
                Text(
                  '${attachment.sizeFormatted} • ${attachment.mimeType}',
                  style: typography.caption(color: colorTokens.textMid),
                ),
              ],
            ),
          ),
          const SizedBox(width: ArDriveSpacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachment.isPreviewable && attachment.data != null) ...[
                ArDriveIconButton(
                  icon: ArDriveIcons.eyeOpen(
                      size: 20, color: colorTokens.iconMid),
                  tooltip: l10n.preview,
                  onPressed: () => _previewAttachment(context, attachment),
                ),
                const SizedBox(width: ArDriveSpacing.xs),
              ],
              ArDriveIconButton(
                icon:
                    ArDriveIcons.download(size: 20, color: colorTokens.iconMid),
                tooltip: l10n.download,
                onPressed: () => _downloadAttachment(attachment),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _getFileIcon(
    EmailAttachment attachment,
    ArDriveColorTokens colorTokens,
  ) {
    final color = colorTokens.iconMid;

    if (attachment.isImage) {
      return ArDriveIcons.image(size: 24, color: color);
    } else if (attachment.isPdf) {
      return ArDriveIcons.fileOutlined(size: 24, color: color);
    } else {
      return ArDriveIcons.file(size: 24, color: color);
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
      showAudioPreview(context, attachment);
    } else if (attachment.isVideo) {
      showVideoPreview(context, attachment);
    }
  }

  void _previewImage(BuildContext context, EmailAttachment attachment) {
    showEmailAttachmentDialog(
      context,
      attachment: attachment,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Center(
          child: Image.memory(attachment.data!, fit: BoxFit.contain),
        ),
      ),
    );
  }

  void _previewText(BuildContext context, EmailAttachment attachment) {
    if (attachment.data == null) return;

    final l10n = appLocalizationsOf(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    String textContent;
    String? note;
    var noteType = ArDriveNoticeType.info;
    try {
      textContent = utf8.decode(attachment.data!, allowMalformed: true);
    } catch (e) {
      textContent = '';
      note = l10n.emailAttachmentUnreadable;
      noteType = ArDriveNoticeType.warning;
    }

    // Limit text preview to avoid performance issues with very large files
    const maxPreviewLength = 1024 * 1024; // 1MB of text
    if (textContent.length > maxPreviewLength) {
      textContent = textContent.substring(0, maxPreviewLength);
      note = l10n.emailAttachmentTruncated;
    }

    showEmailAttachmentDialog(
      context,
      attachment: attachment,
      scrollableContent: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (textContent.isNotEmpty)
            SelectableText(
              textContent,
              style: typography
                  .paragraphSmall(color: colorTokens.textHigh)
                  .copyWith(height: 1.5),
            ),
          if (note != null) ...[
            const SizedBox(height: ArDriveSpacing.md),
            ArDriveNotice(type: noteType, message: note),
          ],
        ],
      ),
    );
  }
}

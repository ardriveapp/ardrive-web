import 'package:ardrive/services/eml_parser/models/email_attachment.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The width an attachment's dialog is drawn at on a screen wide enough for
/// it; the standard dialog narrows it to fit a phone.
const kEmailAttachmentDialogWidth = 800.0;

/// An email attachment opened from its preview: the standard dialog, titled
/// with the file's name and closed from its corner.
///
/// Each kind of attachment drew its own dialog, with a hand-made header, and
/// opened it outside [showArDriveDialog], so the app did not know a dialog
/// was open.
Future<void> showEmailAttachmentDialog(
  BuildContext context, {
  required EmailAttachment attachment,
  required Widget content,
  double width = kEmailAttachmentDialogWidth,
  bool scrollableContent = false,
}) {
  return showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      title: attachment.filename,
      width: width,
      hasCloseButton: true,
      scrollableContent: scrollableContent,
      content: content,
    ),
  );
}

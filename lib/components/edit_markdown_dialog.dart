import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:markdown_editor_plus/widgets/markdown_auto_preview.dart';

Future<void> showMarkdownEditorDialog({
  required BuildContext context,
}) {
  return showModalDialog(
    context,
    () => showArDriveDialog(
      context,
      content: const MarkdownEditorDialog(),
    ),
  );
}

class MarkdownEditorDialog extends StatefulWidget {
  const MarkdownEditorDialog({super.key});

  @override
  _MarkdownEditorDialogState createState() => _MarkdownEditorDialogState();
}

class _MarkdownEditorDialogState extends State<MarkdownEditorDialog> {
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final modalWidth = screenSize.width * 0.8; // 80% of screen width
    final modalHeight = screenSize.height * 0.7; // 70% of screen height

    return ArDriveStandardModalNew(
      title: 'Edit Markdown',
      content: SizedBox(
        width: modalWidth,
        height: modalHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MarkdownAutoPreview(
              decoration: InputDecoration(
                hintText: 'Enter Markdown',
              ),
              emojiConvert: true,
            ),
            // Additional form fields or buttons can go here
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () {
            Navigator.of(context).pop();
          },
          title: 'Cancel',
        ),
        ModalAction(
          action: () {
            // Logic to save or submit the Markdown content
            Navigator.of(context).pop();
          },
          title: 'Save',
          // Logic to enable/disable the button based on form validation
        ),
      ],
    );
  }
}

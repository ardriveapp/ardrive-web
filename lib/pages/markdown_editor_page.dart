import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:markdown_editor_plus/widgets/markdown_auto_preview.dart';

class MarkdownEditorPage extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onSave;
  final MarkdownAutoPreview _markdownAutoPreview;

  MarkdownEditorPage({
    super.key,
    required this.onClose,
    required this.onSave,
    MarkdownAutoPreview? markdownAutoPreview,
  }) : _markdownAutoPreview = markdownAutoPreview ??
            MarkdownAutoPreview(
              decoration: const InputDecoration(
                hintText: 'Enter Markdown',
              ),
              emojiConvert: true,
              expands: true,
              enableToolBar: true,
              toolbarBackground: Colors.blue,
              expandableBackground: Colors.blue[200],
            );

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    late Color backgroundColor;

    if (ArDriveTheme.of(context).isDark()) {
      backgroundColor = colorTokens.containerL3;
    } else {
      backgroundColor = colorTokens.containerL1;
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your New Markdown File',
            style: typography.heading4(
              fontWeight: ArFontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 600,
              child: ArDriveTextFieldNew(
                hintText: 'Give it a title',
                hintStyle: typography.paragraphNormal(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold,
                ),
                onChanged: (text) {
                  // TODO: set the title of the markdown file
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorTokens.textLow,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
                color: backgroundColor,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0), // Optional padding
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(child: _markdownAutoPreview),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ArDriveButtonNew(
                          onPressed: onClose,
                          text: 'Discard',
                          maxHeight: 40,
                          maxWidth: 100,
                          typography: typography,
                          variant: ButtonVariant.primary,
                        ),
                        const SizedBox(width: 8),
                        ArDriveButtonNew(
                          onPressed: onSave,
                          text: 'Save',
                          maxHeight: 40,
                          maxWidth: 100,
                          typography: typography,
                          variant: ButtonVariant.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  get markdownText => _markdownAutoPreview.controller?.text;
}

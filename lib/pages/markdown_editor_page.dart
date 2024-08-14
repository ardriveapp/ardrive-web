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
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Markdown Page'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0), // Optional padding
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _markdownAutoPreview!,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: onClose,
                        child: const Text('Discard'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: onSave,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  get markdownText => _markdownAutoPreview.controller?.text;
}

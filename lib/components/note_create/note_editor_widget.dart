import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive/blocs/note_create/note_create_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Actions that can be performed on the markdown editor
enum EditorAction {
  bold,
  italic,
  strikethrough,
  heading1,
  heading2,
  heading3,
  unorderedList,
  orderedList,
  link,
  code,
  codeBlock,
  quote,
}

/// A custom markdown editor widget with toolbar and preview
class NoteEditorWidget extends StatefulWidget {
  final String initialContent;
  final ValueChanged<String> onChanged;
  final bool showEditor;
  final bool showPreview;
  final NoteViewMode viewMode;
  final ValueChanged<NoteViewMode> onViewModeChanged;
  final bool isMobile;

  const NoteEditorWidget({
    super.key,
    required this.initialContent,
    required this.onChanged,
    this.showEditor = true,
    this.showPreview = true,
    required this.viewMode,
    required this.onViewModeChanged,
    this.isMobile = false,
  });

  @override
  State<NoteEditorWidget> createState() => _NoteEditorWidgetState();
}

class _NoteEditorWidgetState extends State<NoteEditorWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  late ScrollController _editorScrollController;
  late ScrollController _previewScrollController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _focusNode = FocusNode();
    _editorScrollController = ScrollController();
    _previewScrollController = ScrollController();
    _controller.addListener(() {
      widget.onChanged(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _editorScrollController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  void _applyMarkdown(EditorAction action) {
    final selection = _controller.selection;
    final text = _controller.text;

    if (!selection.isValid) {
      // If no selection, just insert at cursor
      _insertMarkdown(action, '');
      return;
    }

    final selectedText = selection.textInside(text);
    _insertMarkdown(action, selectedText);
  }

  void _insertMarkdown(EditorAction action, String selectedText) {
    final selection = _controller.selection;
    String newText;
    int cursorOffset;

    switch (action) {
      case EditorAction.bold:
        newText = '**$selectedText**';
        cursorOffset = selectedText.isEmpty ? 2 : newText.length;
        break;
      case EditorAction.italic:
        newText = '*$selectedText*';
        cursorOffset = selectedText.isEmpty ? 1 : newText.length;
        break;
      case EditorAction.strikethrough:
        newText = '~~$selectedText~~';
        cursorOffset = selectedText.isEmpty ? 2 : newText.length;
        break;
      case EditorAction.heading1:
        newText = '# $selectedText';
        cursorOffset = selectedText.isEmpty ? 2 : newText.length;
        break;
      case EditorAction.heading2:
        newText = '## $selectedText';
        cursorOffset = selectedText.isEmpty ? 3 : newText.length;
        break;
      case EditorAction.heading3:
        newText = '### $selectedText';
        cursorOffset = selectedText.isEmpty ? 4 : newText.length;
        break;
      case EditorAction.unorderedList:
        newText = '- $selectedText';
        cursorOffset = selectedText.isEmpty ? 2 : newText.length;
        break;
      case EditorAction.orderedList:
        newText = '1. $selectedText';
        cursorOffset = selectedText.isEmpty ? 3 : newText.length;
        break;
      case EditorAction.code:
        newText = '`$selectedText`';
        cursorOffset = selectedText.isEmpty ? 1 : newText.length;
        break;
      case EditorAction.codeBlock:
        newText = '```\n$selectedText\n```';
        cursorOffset = selectedText.isEmpty ? 4 : newText.length;
        break;
      case EditorAction.quote:
        newText = '> $selectedText';
        cursorOffset = selectedText.isEmpty ? 2 : newText.length;
        break;
      case EditorAction.link:
        newText = '[$selectedText](url)';
        cursorOffset = selectedText.isEmpty ? 1 : selectedText.length + 3;
        break;
    }

    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(
        selection.start,
        selection.end,
        newText,
      ),
      selection: TextSelection.collapsed(
        offset: selection.start + cursorOffset,
      ),
    );

    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar
        _buildToolbar(context),
        const SizedBox(height: 8),

        // Editor/Preview area
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors.themeBgSurface, // White/light background
              border: Border.all(color: colors.themeBorderDefault),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _buildEditorArea(context),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorArea(BuildContext context) {
    if (widget.showEditor) {
      // Edit mode
      return _buildEditor(context);
    } else {
      // Preview mode
      return _buildPreview(context);
    }
  }

  Widget _buildToolbar(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    final toolbarButtons = [
          _toolbarButton(context, 'B', EditorAction.bold,
              tooltip: 'Bold', fontWeight: FontWeight.bold),
          _toolbarButton(context, 'I', EditorAction.italic,
              tooltip: 'Italic', fontStyle: FontStyle.italic),
          _toolbarButton(context, 'S', EditorAction.strikethrough,
              tooltip: 'Strikethrough',
              textDecoration: TextDecoration.lineThrough),
          _toolbarDivider(),
          _headingDropdownButton(context),
          _toolbarDivider(),
          _toolbarIconButton(context, Icons.format_list_bulleted, EditorAction.unorderedList,
              tooltip: 'Bullet List'),
          _toolbarIconButton(context, Icons.format_list_numbered, EditorAction.orderedList,
              tooltip: 'Numbered List'),
          _toolbarDivider(),
          _toolbarButton(context, '""', EditorAction.quote,
              tooltip: 'Quote'),
          _toolbarButton(context, '</>', EditorAction.code,
              tooltip: 'Inline Code'),
          _toolbarIconButton(context, Icons.code, EditorAction.codeBlock,
              tooltip: 'Code Block'),
          _toolbarDivider(),
          _toolbarIconButton(context, Icons.link, EditorAction.link,
              tooltip: 'Insert Link'),
          _toolbarDivider(),
          _viewToggleButton(context),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.themeBgCanvas,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: widget.isMobile
          ? Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: toolbarButtons
                      .map((button) => Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: button,
                          ))
                      .toList(),
                ),
              ),
            )
          : Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: toolbarButtons,
            ),
    );
  }

  Widget _toolbarButton(
    BuildContext context,
    String label,
    EditorAction action, {
    String? tooltip,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextDecoration? textDecoration,
  }) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        onTap: () => _applyMarkdown(action),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.themeBgSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.themeBorderDefault),
          ),
          child: Text(
            label,
            style: typography
                .paragraphSmall(fontWeight: ArFontWeight.bold)
                .copyWith(
                  fontWeight: fontWeight,
                  fontStyle: fontStyle,
                  decoration: textDecoration,
                ),
          ),
        ),
      ),
    );
  }

  Widget _toolbarIconButton(
    BuildContext context,
    IconData icon,
    EditorAction action, {
    String? tooltip,
  }) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: () => _applyMarkdown(action),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.themeBgSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.themeBorderDefault),
          ),
          child: Icon(
            icon,
            size: 16,
            color: colors.themeFgDefault,
          ),
        ),
      ),
    );
  }

  Widget _toolbarDivider() {
    return Container(
      width: 1,
      height: 24,
      color: ArDriveTheme.of(context).themeData.colors.themeBorderDefault,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _headingDropdownButton(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colors;

    return PopupMenuButton<EditorAction>(
      tooltip: 'Heading',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.themeBgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.themeBorderDefault),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'H',
              style: typography
                  .paragraphSmall(fontWeight: ArFontWeight.bold),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: colors.themeFgDefault),
          ],
        ),
      ),
      onSelected: (action) => _applyMarkdown(action),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: EditorAction.heading1,
          child: Text('Heading 1', style: typography.paragraphNormal()),
        ),
        PopupMenuItem(
          value: EditorAction.heading2,
          child: Text('Heading 2', style: typography.paragraphNormal()),
        ),
        PopupMenuItem(
          value: EditorAction.heading3,
          child: Text('Heading 3', style: typography.paragraphNormal()),
        ),
      ],
    );
  }

  Widget _viewToggleButton(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final isEditMode = widget.viewMode == NoteViewMode.editOnly;

    return Tooltip(
      message: isEditMode ? 'Preview' : 'Edit',
      child: InkWell(
        onTap: () {
          // Toggle between edit and preview
          final newMode = isEditMode
              ? NoteViewMode.previewOnly
              : NoteViewMode.editOnly;
          widget.onViewModeChanged(newMode);
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.themeBgSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.themeBorderDefault),
          ),
          child: Icon(
            isEditMode ? Icons.menu_book_outlined : Icons.edit_outlined,
            size: 16,
            color: colors.themeFgDefault,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colors;

    // TextField has its own internal scrolling, no need for wrapper
    // Background color applied to parent container
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      scrollController: _editorScrollController,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      textInputAction: TextInputAction.newline,
      style: typography.paragraphNormal().copyWith(
            fontFamily: 'Courier New',
            fontFamilyFallback: const ['monospace'],
          ),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.all(16),
        border: InputBorder.none,
        hintText: 'Write your note in markdown...',
        hintStyle: typography.paragraphNormal().copyWith(
              color: colors.themeFgSubtle,
            ),
      ),
      keyboardType: TextInputType.multiline,
    );
  }

  Widget _buildPreview(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colors;

    // Background color applied to parent container
    if (_controller.text.isEmpty) {
      return SingleChildScrollView(
        controller: _previewScrollController,
        padding: const EdgeInsets.all(16),
        child: Text(
          'Preview will appear here...',
          style: typography.paragraphNormal().copyWith(
                color: colors.themeFgSubtle,
                fontStyle: FontStyle.italic,
              ),
        ),
      );
    }

    return ArDriveScrollBar(
      controller: _previewScrollController,
      alwaysVisible: true,
      child: Markdown(
        controller: _previewScrollController,
        data: _controller.text,
        selectable: true,
        padding: const EdgeInsets.all(16),
        extensionSet: md.ExtensionSet.gitHubWeb,
        imageBuilder: (uri, title, alt) {
        return Image.network(
          uri.toString(),
          errorBuilder: (context, error, stackTrace) {
            // Handle image loading errors (e.g., SVG images, network issues)
            return Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.themeBgCanvas,
                border: Border.all(color: colors.themeBorderDefault),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 16,
                    color: colors.themeFgSubtle,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      alt ?? title ?? 'Image',
                      style: typography.paragraphSmall().copyWith(
                        color: colors.themeFgSubtle,
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      styleSheet: MarkdownStyleSheet(
        p: typography.paragraphNormal().copyWith(
              color: colors.themeFgDefault,
            ),
        h1: typography.heading1().copyWith(
              color: colors.themeFgDefault,
            ),
        h2: typography.heading2().copyWith(
              color: colors.themeFgDefault,
            ),
        h3: typography.heading3().copyWith(
              color: colors.themeFgDefault,
            ),
        h4: typography.heading4().copyWith(
              color: colors.themeFgDefault,
            ),
        h5: typography.heading5().copyWith(
              color: colors.themeFgDefault,
            ),
        h6: typography.heading6().copyWith(
              color: colors.themeFgDefault,
            ),
        listBullet: typography.paragraphNormal().copyWith(
              color: colors.themeFgDefault,
            ),
        code: typography.paragraphNormal().copyWith(
              fontFamily: 'Courier New',
              fontFamilyFallback: const ['monospace'],
              backgroundColor: colors.themeBgCanvas,
              color: colors.themeFgDefault,
            ),
        codeblockDecoration: BoxDecoration(
          color: colors.themeBgCanvas,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.themeBorderDefault),
            ),
        blockquote: typography.paragraphNormal().copyWith(
              color: colors.themeFgSubtle,
              fontStyle: FontStyle.italic,
            ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: colors.themeBorderDefault,
              width: 4,
            ),
          ),
        ),
        strong: typography.paragraphNormal(
          fontWeight: ArFontWeight.bold,
        ).copyWith(
              color: colors.themeFgDefault,
            ),
        em: typography.paragraphNormal().copyWith(
              fontStyle: FontStyle.italic,
              color: colors.themeFgDefault,
            ),
      ),
      ),
    );
  }
}

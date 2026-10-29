import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive/blocs/note_create/note_create_state.dart';
import 'package:ardrive/components/markdown_style_sheet.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
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
  final NoteViewMode viewMode;
  final ValueChanged<NoteViewMode> onViewModeChanged;
  final bool isMobile;

  const NoteEditorWidget({
    super.key,
    required this.initialContent,
    required this.onChanged,
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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // One field, like a text field: the toolbar sits inside its top edge, so
    // the formatting reads as belonging to the text below it.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorTokens.inputDefault,
        border: Border.all(color: colorTokens.strokeMid),
        borderRadius: BorderRadius.circular(_fieldRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_fieldRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(context),
            Divider(height: 1, thickness: 1, color: colorTokens.strokeLow),
            Expanded(child: _buildEditorArea(context)),
          ],
        ),
      ),
    );
  }

  /// [ArDriveTextFieldNew]'s corner radius.
  static const _fieldRadius = 6.0;

  Widget _buildEditorArea(BuildContext context) {
    switch (widget.viewMode) {
      case NoteViewMode.editOnly:
        return _buildEditor(context);
      case NoteViewMode.previewOnly:
        return _buildPreview(context);
    }
  }

  Widget _buildToolbar(BuildContext context) {
    final localizations = appLocalizationsOf(context);

    final toolbarButtons = [
      _toolbarButton(context, 'B', EditorAction.bold,
          tooltip: localizations.markdownEditorBold,
          fontWeight: FontWeight.bold),
      _toolbarButton(context, 'I', EditorAction.italic,
          tooltip: localizations.markdownEditorItalic,
          fontStyle: FontStyle.italic),
      _toolbarButton(context, 'S', EditorAction.strikethrough,
          tooltip: localizations.markdownEditorStrikethrough,
          textDecoration: TextDecoration.lineThrough),
      _toolbarDivider(),
      _headingDropdownButton(context),
      _toolbarDivider(),
      _toolbarIconButton(
          context, Icons.format_list_bulleted, EditorAction.unorderedList,
          tooltip: localizations.markdownEditorBulletList),
      _toolbarIconButton(
          context, Icons.format_list_numbered, EditorAction.orderedList,
          tooltip: localizations.markdownEditorNumberedList),
      _toolbarDivider(),
      _toolbarButton(context, '""', EditorAction.quote,
          tooltip: localizations.markdownEditorQuote),
      _toolbarButton(context, '</>', EditorAction.code,
          tooltip: localizations.markdownEditorInlineCode),
      _toolbarIconButton(context, Icons.code, EditorAction.codeBlock,
          tooltip: localizations.markdownEditorCodeBlock),
      _toolbarDivider(),
      _toolbarIconButton(context, Icons.link, EditorAction.link,
          tooltip: localizations.markdownEditorInsertLink),
      _toolbarDivider(),
      _viewToggleButton(context),
    ];

    return Padding(
      padding: const EdgeInsets.all(ArDriveSpacing.xxs),
      child: widget.isMobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: toolbarButtons,
              ),
            )
          : Wrap(
              spacing: 2,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: toolbarButtons,
            ),
    );
  }

  /// A toolbar control: no box of its own, a tint on hover and press, and a
  /// tooltip naming what it does, which is also its accessible name.
  Widget _toolbarControl(
    BuildContext context, {
    required String tooltip,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Tooltip(
      message: tooltip,
      // The control names itself below; the tooltip's own node would say it
      // twice.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ArDriveRadius.sm),
            hoverColor: colorTokens.buttonSecondaryHover,
            highlightColor: colorTokens.buttonSecondaryPress,
            splashColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: ArDriveSpacing.xs),
                child: Center(widthFactor: 1, child: child),
              ),
            ),
          ),
        ),
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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return _toolbarControl(
      context,
      tooltip: tooltip ?? label,
      onTap: () => _applyMarkdown(action),
      child: Text(
        label,
        style: typography
            .paragraphNormal(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.semiBold,
            )
            .copyWith(
              fontWeight: fontWeight,
              fontStyle: fontStyle,
              decoration: textDecoration,
            ),
      ),
    );
  }

  Widget _toolbarIconButton(
    BuildContext context,
    IconData icon,
    EditorAction action, {
    required String tooltip,
  }) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return _toolbarControl(
      context,
      tooltip: tooltip,
      onTap: () => _applyMarkdown(action),
      child: Icon(icon, size: 18, color: colorTokens.iconMid),
    );
  }

  Widget _toolbarDivider() {
    return Container(
      width: 1,
      height: 20,
      color: ArDriveTheme.of(context).themeData.colorTokens.strokeMid,
      margin: const EdgeInsets.symmetric(horizontal: ArDriveSpacing.xxs),
    );
  }

  Widget _headingDropdownButton(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final localizations = appLocalizationsOf(context);

    return ArDriveChoiceMenu<EditorAction>(
      // Actions, not a value: no row is ticked.
      value: null,
      onSelected: _applyMarkdown,
      debugLabel: 'heading',
      choices: [
        ArDriveChoice(
          value: EditorAction.heading1,
          label: localizations.markdownEditorHeading1,
        ),
        ArDriveChoice(
          value: EditorAction.heading2,
          label: localizations.markdownEditorHeading2,
        ),
        ArDriveChoice(
          value: EditorAction.heading3,
          label: localizations.markdownEditorHeading3,
        ),
      ],
      // As the toolbar's other controls are: a tooltip kept out of the
      // semantics, and their hover tint.
      builder: (context, isOpen, toggle) => Tooltip(
        message: localizations.markdownEditorHeading,
        excludeFromSemantics: true,
        child: ArDriveChoiceButton(
          toggle: toggle,
          semanticLabel: localizations.markdownEditorHeading,
          builder: (context, hovered, focused) => Container(
            decoration: BoxDecoration(
              color:
                  hovered || focused ? colorTokens.buttonSecondaryHover : null,
              borderRadius: BorderRadius.circular(ArDriveRadius.sm),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              child: Padding(
                padding:
                    const EdgeInsets.only(left: ArDriveSpacing.xs, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'H',
                      style: typography.paragraphNormal(
                        color: colorTokens.textHigh,
                        fontWeight: ArFontWeight.bold,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down,
                        size: 18, color: colorTokens.iconMid),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewToggleButton(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final localizations = appLocalizationsOf(context);
    final isEditMode = widget.viewMode == NoteViewMode.editOnly;

    return _toolbarControl(
      context,
      tooltip: isEditMode
          ? localizations.markdownEditorPreview
          : localizations.markdownEditorEdit,
      onTap: () => widget.onViewModeChanged(
        isEditMode ? NoteViewMode.previewOnly : NoteViewMode.editOnly,
      ),
      child: Icon(
        isEditMode ? Icons.menu_book_outlined : Icons.edit_outlined,
        size: 18,
        color: colorTokens.iconMid,
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // TextField has its own internal scrolling, no need for wrapper.
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      scrollController: _editorScrollController,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      textInputAction: TextInputAction.newline,
      cursorColor: colorTokens.textHigh,
      // Markdown source, so the monospace face: its markup lines up.
      style: typography.code(color: colorTokens.textHigh),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.all(ArDriveSpacing.md),
        border: InputBorder.none,
        hintText: appLocalizationsOf(context).markdownEditorPlaceholder,
        hintStyle: typography.paragraphNormal(color: colorTokens.textLow),
      ),
      keyboardType: TextInputType.multiline,
    );
  }

  Widget _buildPreview(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    if (_controller.text.isEmpty) {
      return SingleChildScrollView(
        controller: _previewScrollController,
        padding: const EdgeInsets.all(ArDriveSpacing.md),
        child: Text(
          appLocalizationsOf(context).markdownPreviewPlaceholder,
          style: typography
              .paragraphNormal(color: colorTokens.textLow)
              .copyWith(fontStyle: FontStyle.italic),
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
        padding: const EdgeInsets.all(ArDriveSpacing.md),
        extensionSet: md.ExtensionSet.gitHubWeb,
        imageBuilder: (uri, title, alt) {
          return Image.network(
            uri.toString(),
            // An image that can't load (an SVG, a network failure) shows as
            // its alt text.
            errorBuilder: (context, error, stackTrace) => Container(
              padding: const EdgeInsets.all(ArDriveSpacing.xs),
              decoration: BoxDecoration(
                color: colorTokens.containerL2,
                border: Border.all(color: colorTokens.strokeLow),
                borderRadius: BorderRadius.circular(ArDriveRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 16,
                    color: colorTokens.iconLow,
                  ),
                  const SizedBox(width: ArDriveSpacing.xs),
                  Flexible(
                    child: Text(
                      alt ??
                          title ??
                          appLocalizationsOf(context).markdownImageAltText,
                      style: typography
                          .paragraphSmall(color: colorTokens.textLow)
                          .copyWith(fontStyle: FontStyle.italic),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        // The note as it will look once saved, at the reading size.
        styleSheet: arDriveMarkdownStyleSheet(
          typography,
          colorTokens,
          isFullScreen: true,
        ),
      ),
    );
  }
}

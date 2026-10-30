import 'dart:async';

import 'package:ardrive/components/markdown_style_sheet.dart';
import 'package:ardrive/components/note_create/note_create_form.dart';
import 'package:ardrive/publication/domain/publication_hosts.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/file_type_label.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class DocumentPreviewWidget extends StatefulWidget {
  final String filename;
  final String content;
  final String contentType;
  final bool isSharePage;
  final bool isFullScreen;
  final FileDataTableItem? fileItem; // For edit functionality

  const DocumentPreviewWidget({
    super.key,
    required this.filename,
    required this.content,
    required this.contentType,
    required this.isSharePage,
    this.isFullScreen = false,
    this.fileItem,
  });

  @override
  State<DocumentPreviewWidget> createState() => _DocumentPreviewWidgetState();
}

class _DocumentPreviewWidgetState extends State<DocumentPreviewWidget> {
  late ScrollController _scrollController;
  bool _showScrollToTop = false;
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;
  bool _showAsMarkdown = true; // Toggle between markdown and plain text view

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    if (widget.isFullScreen) {
      _resetHideControlsTimer();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _cancelHideControlsTimer();
    super.dispose();
  }

  bool _isMarkdown() {
    return widget.contentType == 'text/markdown' ||
        widget.contentType == 'text/x-markdown';
  }

  Widget _buildContentWidget(
    ArdriveTypographyNew typography,
    ArDriveColorTokens colorTokens, {
    bool isFullScreen = false,
  }) {
    if (_isMarkdown() && _showAsMarkdown) {
      // Render markdown with proper formatting using flutter_markdown
      return MarkdownBody(
        data: widget.content,
        selectable: true,
        imageBuilder: (uri, title, alt) {
          Widget placeholder() => Container(
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
              );
          // A publication fetches only from its own host and gateway, so an
          // image a note links to elsewhere shows as its alt text.
          if (PublicationMode.isOn &&
              !publicationMayFetch(
                uri,
                page: Uri.base,
                gateway: Uri.parse(context
                    .read<ConfigService>()
                    .config
                    .arweaveGatewayForDataRequest
                    .url),
              )) {
            return placeholder();
          }
          return Image.network(
            uri.toString(),
            // Handle image loading errors (e.g., SVG images, network issues)
            errorBuilder: (context, error, stackTrace) => placeholder(),
          );
        },
        styleSheet: arDriveMarkdownStyleSheet(
          typography,
          colorTokens,
          isFullScreen: isFullScreen,
        ),
      );
    } else {
      // Render as plain text, in the monospace face: a text file's columns
      // and indentation only line up in one. The inline view had no colour of
      // its own, so it took whatever the surrounding text style happened to
      // be.
      return Text(
        widget.content,
        style: isFullScreen
            ? typography.code(color: colorTokens.textHigh).copyWith(height: 1.7)
            : typography.code(color: colorTokens.textHigh, fontSize: 11),
      );
    }
  }

  void _scrollListener() {
    if (_scrollController.offset > 200) {
      if (!_showScrollToTop) {
        setState(() {
          _showScrollToTop = true;
        });
      }
    } else {
      if (_showScrollToTop) {
        setState(() {
          _showScrollToTop = false;
        });
      }
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _copyToClipboard() => copyPreviewText(context, widget.content);

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.isFullScreen) {
        _hideControls();
      }
    });
  }

  void _cancelHideControlsTimer() {
    _hideControlsTimer?.cancel();
  }

  void _showControls() {
    setState(() {
      _controlsVisible = true;
    });
    if (widget.isFullScreen) {
      _resetHideControlsTimer();
    }
  }

  void _hideControls() {
    setState(() {
      _controlsVisible = false;
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  Future<void> _toggleFullScreen() async {
    if (widget.isFullScreen) {
      Navigator.of(context).pop();
    } else {
      await Navigator.of(context).push(
        PageRouteBuilder(
          barrierDismissible: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, __) => Scaffold(
            backgroundColor:
                ArDriveTheme.of(context).themeData.colorTokens.containerL1,
            body: DocumentPreviewWidget(
              filename: widget.filename,
              content: widget.content,
              contentType: widget.contentType,
              isSharePage: widget.isSharePage,
              isFullScreen: true,
              fileItem: widget.fileItem,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _editNote() async {
    final fileItem = widget.fileItem;
    if (fileItem == null) return;

    await promptToEditNote(
      context,
      driveId: fileItem.driveId,
      parentFolderId: fileItem.parentFolderId,
      fileId: fileItem.fileId,
      fileName: fileItem.name,
      fileContent: widget.content,
      fileSize: fileItem.size ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    if (widget.isFullScreen) {
      return _buildFullScreenLayout(colorTokens, typography);
    } else {
      return _buildNormalLayout(colorTokens, typography);
    }
  }

  Widget _buildNormalLayout(
    ArDriveColorTokens colorTokens,
    ArdriveTypographyNew typography,
  ) {
    return Column(
      children: [
        // Content area
        Expanded(
          child: Stack(
            children: [
              Container(
                color: colorTokens.containerRaised,
                child: ArDriveScrollBar(
                  controller: _scrollController,
                  alwaysVisible: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(ArDriveSpacing.md),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _buildContentWidget(typography, colorTokens,
                          isFullScreen: false),
                    ),
                  ),
                ),
              ),
              // Scroll to top button
              if (_showScrollToTop)
                Positioned(
                  bottom: ArDriveSpacing.md,
                  right: ArDriveSpacing.md,
                  child: _scrollToTopButton(colorTokens),
                ),
            ],
          ),
        ),
        // Bottom action bar
        _buildActionBar(colorTokens, typography),
      ],
    );
  }

  Widget _buildFullScreenLayout(
    ArDriveColorTokens colorTokens,
    ArdriveTypographyNew typography,
  ) {
    return MouseRegion(
      onHover: (_) {
        _showControls();
      },
      child: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Content
            Container(
              color: colorTokens.containerL1,
              padding: EdgeInsets.only(
                bottom: _controlsVisible ? 100 : 0,
              ),
              child: ArDriveScrollBar(
                controller: _scrollController,
                alwaysVisible: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(ArDriveSpacing.lg),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: _buildContentWidget(typography, colorTokens,
                          isFullScreen: true),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _buildActionBar(colorTokens, typography,
                    isFullScreen: true),
              ),
            ),
            // Scroll to top button
            if (_showScrollToTop && _controlsVisible)
              Positioned(
                bottom: 120,
                right: ArDriveSpacing.md,
                child: _scrollToTopButton(colorTokens),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scrollToTopButton(ArDriveColorTokens colorTokens) {
    return ArDriveIconButton(
      icon: ArDriveIcons.chevronUp(size: 20, color: colorTokens.iconMid),
      tooltip: appLocalizationsOf(context).previewScrollToTop,
      onPressed: _scrollToTop,
    );
  }

  Widget _buildActionBar(
    ArDriveColorTokens colorTokens,
    ArdriveTypographyNew typography, {
    bool isFullScreen = false,
  }) {
    final l10n = appLocalizationsOf(context);
    final fileNameWithoutExtension =
        getBasenameWithoutExtension(filePath: widget.filename);

    Widget iconButton({
      required String tooltip,
      required Widget icon,
      required VoidCallback onPressed,
    }) =>
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          color: colorTokens.iconMid,
          icon: icon,
        );

    return Container(
      padding: const EdgeInsets.all(ArDriveSpacing.lg),
      color:
          isFullScreen ? colorTokens.containerL2 : colorTokens.containerRaised,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: fileNameWithoutExtension,
                  child: Text(
                    fileNameWithoutExtension,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: typography.paragraphLarge(
                      color: colorTokens.textHigh,
                      fontWeight: ArFontWeight.bold,
                    ),
                  ),
                ),
                // textLow, not the disabled grey it was: a type label is read,
                // and that grey was under 2:1 on the light preview.
                Text(
                  fileTypeLabel(
                    contentType: widget.contentType,
                    fileName: widget.filename,
                    manifestLabel: l10n.manifestFileType,
                  ),
                  style: typography.paragraphLarge(color: colorTokens.textLow),
                ),
              ],
            ),
          ),
          Row(
            children: [
              iconButton(
                tooltip: l10n.previewCopyText,
                icon: ArDriveIcons.copy(size: 20, color: colorTokens.iconMid),
                onPressed: _copyToClipboard,
              ),
              if (_isMarkdown()) ...[
                const SizedBox(width: ArDriveSpacing.xs),
                iconButton(
                  tooltip: _showAsMarkdown
                      ? l10n.previewShowAsText
                      : l10n.previewShowAsMarkdown,
                  icon: Icon(
                    _showAsMarkdown
                        ? Icons.text_fields
                        : Icons.article_outlined,
                    size: 24,
                  ),
                  onPressed: () {
                    setState(() {
                      _showAsMarkdown = !_showAsMarkdown;
                    });
                  },
                ),
              ],
              // A publication is read-only.
              if (_isMarkdown() &&
                  widget.fileItem != null &&
                  !widget.isSharePage &&
                  !PublicationMode.isOn) ...[
                const SizedBox(width: ArDriveSpacing.xs),
                iconButton(
                  tooltip: l10n.editNote,
                  icon: ArDriveIcons.edit(size: 20, color: colorTokens.iconMid),
                  onPressed: _editNote,
                ),
              ],
              const SizedBox(width: ArDriveSpacing.xs),
              iconButton(
                tooltip: isFullScreen ? l10n.collapse : l10n.expand,
                icon: Icon(
                  isFullScreen
                      ? Icons.fullscreen_exit_outlined
                      : Icons.fullscreen_outlined,
                  size: 24,
                ),
                onPressed: _toggleFullScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Copies a preview's whole text and says whether that worked: a browser can
/// refuse a write it doesn't count as the reader's own. It used to say
/// "Copied to clipboard" either way.
Future<void> copyPreviewText(BuildContext context, String text) async {
  final l10n = appLocalizationsOf(context);
  final messenger = ScaffoldMessenger.of(context);

  // Asked for at once, inside the tap, then waited on.
  final write = Clipboard.setData(ClipboardData(text: text));
  bool copied;
  try {
    await write;
    copied = true;
  } catch (_) {
    copied = false;
  }

  showArDriveToast(
    messenger,
    text: copied ? l10n.copied : l10n.couldNotCopy,
    type: copied ? ArDriveStatusType.success : ArDriveStatusType.error,
    duration: const Duration(seconds: 2),
  );
}

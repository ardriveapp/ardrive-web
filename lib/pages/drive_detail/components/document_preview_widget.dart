import 'dart:async';

import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class DocumentPreviewWidget extends StatefulWidget {
  final String filename;
  final String content;
  final String contentType;
  final bool isSharePage;
  final bool isFullScreen;

  const DocumentPreviewWidget({
    super.key,
    required this.filename,
    required this.content,
    required this.contentType,
    required this.isSharePage,
    this.isFullScreen = false,
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

  Widget _buildContentWidget(dynamic typography, dynamic colors, {bool isFullScreen = false}) {
    if (_isMarkdown() && _showAsMarkdown) {
      // Render markdown with proper formatting using flutter_markdown
      return MarkdownBody(
        data: widget.content,
        selectable: true,
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
          p: isFullScreen
              ? typography.paragraphNormal(
                  fontWeight: ArFontWeight.book,
                  color: colors.themeFgDefault,
                ).copyWith(height: 1.8)
              : typography.paragraphSmall(
                  fontWeight: ArFontWeight.book,
                  color: colors.themeFgDefault,
                ).copyWith(height: 1.5),
          h1: isFullScreen
              ? typography.heading1(color: colors.themeFgDefault)
              : typography.heading3(color: colors.themeFgDefault),
          h2: isFullScreen
              ? typography.heading2(color: colors.themeFgDefault)
              : typography.heading4(color: colors.themeFgDefault),
          h3: isFullScreen
              ? typography.heading3(color: colors.themeFgDefault)
              : typography.heading5(color: colors.themeFgDefault),
          h4: isFullScreen
              ? typography.heading4(color: colors.themeFgDefault)
              : typography.heading6(color: colors.themeFgDefault),
          h5: typography.heading5(color: colors.themeFgDefault),
          h6: typography.heading6(color: colors.themeFgDefault),
          listBullet: typography.paragraphNormal(color: colors.themeFgDefault),
          code: typography.paragraphSmall(
            fontWeight: ArFontWeight.book,
          ).copyWith(
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
          ).copyWith(color: colors.themeFgDefault),
          em: typography.paragraphNormal().copyWith(
            fontStyle: FontStyle.italic,
            color: colors.themeFgDefault,
          ),
        ),
      );
    } else {
      // Render as plain text
      return Text(
        widget.content,
        style: isFullScreen
            ? typography.paragraphNormal(
                fontWeight: ArFontWeight.book,
                color: colors.themeFgDefault,
              ).copyWith(
                fontFamily: 'Courier New',
                height: 1.8,
              )
            : typography.paragraphSmall(
                fontWeight: ArFontWeight.book,
              ).copyWith(
                fontFamily: 'Courier New',
                height: 1.5,
              ),
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

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.content));
    final theme = ArDriveTheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: theme.themeData.colors.themeBgSurface,
        content: Text(
          'Copied to clipboard',
          style: TextStyle(color: theme.themeData.colors.themeFgDefault),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
            backgroundColor: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
            body: DocumentPreviewWidget(
              filename: widget.filename,
              content: widget.content,
              contentType: widget.contentType,
              isSharePage: widget.isSharePage,
              isFullScreen: true,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context);
    final colors = theme.themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    if (widget.isFullScreen) {
      return _buildFullScreenLayout(colors, typography);
    } else {
      return _buildNormalLayout(colors, typography);
    }
  }

  Widget _buildNormalLayout(dynamic colors, dynamic typography) {
    return Column(
      children: [
        // Content area
        Expanded(
          child: Stack(
            children: [
              Container(
                color: colors.themeBgSurface,
                child: ArDriveScrollBar(
                  controller: _scrollController,
                  alwaysVisible: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _buildContentWidget(typography, colors, isFullScreen: false),
                    ),
                  ),
                ),
              ),
              // Scroll to top button
              if (_showScrollToTop)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: ArDriveIconButton(
                    icon: ArDriveIcons.chevronUp(size: 20),
                    tooltip: 'Scroll to top',
                    onPressed: _scrollToTop,
                  ),
                ),
            ],
          ),
        ),
        // Bottom action bar
        _buildActionBar(colors, typography),
      ],
    );
  }

  Widget _buildFullScreenLayout(dynamic colors, dynamic typography) {
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
              color: colors.themeBgSurface,
              padding: EdgeInsets.only(
                bottom: _controlsVisible ? 100 : 0,
              ),
              child: ArDriveScrollBar(
                controller: _scrollController,
                alwaysVisible: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: _buildContentWidget(typography, colors, isFullScreen: true),
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
                child: Container(
                  color: colors.themeBgCanvas,
                  child: _buildActionBar(colors, typography, isFullScreen: true),
                ),
              ),
            ),
            // Scroll to top button
            if (_showScrollToTop && _controlsVisible)
              Positioned(
                bottom: 120,
                right: 16,
                child: ArDriveIconButton(
                  icon: ArDriveIcons.chevronUp(size: 20),
                  tooltip: 'Scroll to top',
                  onPressed: _scrollToTop,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(dynamic colors, dynamic typography, {bool isFullScreen = false}) {
    final fileNameWithoutExtension = getBasenameWithoutExtension(filePath: widget.filename);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      color: colors.themeBgCanvas,
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
                    style: ArDriveTypography.body.smallBold700(
                      color: colors.themeFgDefault,
                    ),
                  ),
                ),
                Text(
                  getFileTypeFromMime(contentType: widget.contentType).toUpperCase(),
                  style: ArDriveTypography.body.smallRegular(
                    color: colors.themeFgDisabled,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              ArDriveIconButton(
                icon: ArDriveIcons.copy(size: 20),
                tooltip: 'Copy to clipboard',
                onPressed: _copyToClipboard,
              ),
              if (_isMarkdown()) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: _showAsMarkdown ? 'View as plain text' : 'View as markdown',
                  child: IconButton(
                    icon: Icon(
                      _showAsMarkdown ? Icons.text_fields : Icons.article_outlined,
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        _showAsMarkdown = !_showAsMarkdown;
                      });
                    },
                  ),
                ),
              ],
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  isFullScreen ? Icons.fullscreen_exit_outlined : Icons.fullscreen_outlined,
                  size: 24,
                ),
                tooltip: isFullScreen ? 'Exit fullscreen' : 'Expand',
                onPressed: _toggleFullScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}


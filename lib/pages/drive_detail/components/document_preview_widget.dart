import 'dart:async';

import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
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
            backgroundColor: Colors.black,
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
                child: Scrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      widget.content,
                      style: typography.paragraphSmall(
                        fontWeight: ArFontWeight.book,
                      ).copyWith(
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
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
              color: Colors.black,
              padding: EdgeInsets.only(
                bottom: _controlsVisible ? 100 : 0,
              ),
              child: Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: SelectableText(
                        widget.content,
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.book,
                          color: Colors.white,
                        ).copyWith(
                          fontFamily: 'monospace',
                          height: 1.8,
                        ),
                      ),
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
                  icon: ArDriveIcons.chevronUp(size: 20, color: Colors.white),
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
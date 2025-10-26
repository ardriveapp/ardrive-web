import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/pages/drive_detail/components/email_attachment_list.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class EmailPreviewWidget extends StatefulWidget {
  final FsEntryPreviewEmail state;
  final bool isSharePage;
  final bool isFullScreen;

  const EmailPreviewWidget({
    super.key,
    required this.state,
    this.isSharePage = false,
    this.isFullScreen = false,
  });

  @override
  State<EmailPreviewWidget> createState() => _EmailPreviewWidgetState();
}

class _EmailPreviewWidgetState extends State<EmailPreviewWidget> {
  late ScrollController _scrollController;
  bool _showScrollToTop = false;
  bool _showHtml = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);

    // Auto-select HTML if text body is empty
    if (widget.state.email.textBody.trim().isEmpty &&
        widget.state.email.htmlBody.isNotEmpty) {
      _showHtml = true;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.offset > 200) {
      if (!_showScrollToTop) {
        setState(() => _showScrollToTop = true);
      }
    } else {
      if (_showScrollToTop) {
        setState(() => _showScrollToTop = false);
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

  void _copyEmailToClipboard() {
    final buffer = StringBuffer();
    buffer.writeln('From: ${widget.state.email.from}');
    buffer.writeln('To: ${widget.state.email.to}');
    if (widget.state.email.cc.isNotEmpty) {
      buffer.writeln('CC: ${widget.state.email.cc}');
    }
    buffer.writeln('Subject: ${widget.state.email.subject}');
    buffer.writeln('Date: ${widget.state.email.date}');
    buffer.writeln();

    // Use textBody if available, otherwise fall back to stripped HTML body
    final bodyContent = widget.state.email.textBody.isNotEmpty
        ? widget.state.email.textBody
        : _stripHtmlTags(widget.state.email.htmlBody);
    buffer.writeln(bodyContent);

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    final theme = ArDriveTheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: theme.themeData.colors.themeBgSurface,
        content: Text(
          'Email content copied to clipboard',
          style: TextStyle(color: theme.themeData.colors.themeFgDefault),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
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
            body: EmailPreviewWidget(
              state: widget.state,
              isSharePage: widget.isSharePage,
              isFullScreen: true,
            ),
          ),
        ),
      );
    }
  }

  /// Strip HTML tags and decode common HTML entities to plain text
  String _stripHtmlTags(String html) {
    if (html.isEmpty) return '';

    // Remove HTML tags
    String text = html.replaceAll(RegExp(r'<[^>]*>'), ' ');

    // Decode common HTML entities
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");

    // Collapse multiple whitespace/newlines into single spaces
    text = text.replaceAll(RegExp(r'\s+'), ' ');

    return text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildEmailHeaders(colors, typography),
                        const SizedBox(height: 24),
                        _buildEmailBody(colors, typography),
                        if (widget.state.email.hasAttachments) ...[
                          const SizedBox(height: 16),
                          EmailAttachmentList(
                            attachments: widget.state.email.attachments,
                          ),
                        ],
                      ],
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

  Widget _buildEmailHeaders(dynamic colors, dynamic typography) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgCanvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject
          Text(
            widget.state.email.subject,
            style: typography.heading6(
              fontWeight: ArFontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: colors.themeBorderDefault, height: 1),
          const SizedBox(height: 16),
          // From
          _buildHeaderRow('From', widget.state.email.from, colors, typography),
          const SizedBox(height: 8),
          // To
          _buildHeaderRow('To', widget.state.email.to, colors, typography),
          // CC (if present)
          if (widget.state.email.cc.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildHeaderRow('CC', widget.state.email.cc, colors, typography),
          ],
          // Date
          const SizedBox(height: 8),
          _buildHeaderRow(
            'Date',
            _formatDate(widget.state.email.date),
            colors,
            typography,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(
    String label,
    String value,
    dynamic colors,
    dynamic typography,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: typography.paragraphSmall(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeFgMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: typography.paragraphSmall(),
          ),
        ),
      ],
    );
  }

  Widget _buildViewToggle(dynamic colors, dynamic typography) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: colors.themeBgSurface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: colors.themeBorderDefault,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            label: 'Plain Text',
            isSelected: !_showHtml,
            onTap: () => setState(() => _showHtml = false),
            colors: colors,
            typography: typography,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
          ),
          Container(
            width: 1,
            height: 32,
            color: colors.themeBorderDefault,
          ),
          _buildToggleButton(
            label: 'HTML',
            isSelected: _showHtml,
            onTap: () => setState(() => _showHtml = true),
            colors: colors,
            typography: typography,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required dynamic colors,
    required dynamic typography,
    required BorderRadius borderRadius,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.themeAccentBrand : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: Text(
          label,
          style: typography.paragraphSmall(
            color: isSelected
                ? colors.themeFgOnAccent
                : colors.themeFgDefault,
            fontWeight: isSelected ? ArFontWeight.semiBold : ArFontWeight.book,
          ),
        ),
      ),
    );
  }

  Widget _buildEmailBody(dynamic colors, dynamic typography) {
    final hasHtmlBody = widget.state.email.hasHtmlBody;
    final hasTextBody = widget.state.email.textBody.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgCanvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle between HTML and Text (if both available)
          if (hasHtmlBody && hasTextBody)
            Row(
              children: [
                Text(
                  'View as:',
                  style: typography.paragraphSmall(
                    color: colors.themeFgMuted,
                  ),
                ),
                const SizedBox(width: 12),
                _buildViewToggle(colors, typography),
              ],
            ),
          if (hasHtmlBody && hasTextBody) const SizedBox(height: 16),
          // Body content
          SelectableText(
            _showHtml && hasHtmlBody
                ? widget.state.email.htmlBody
                : widget.state.email.textBody,
            style: typography.paragraphSmall(
              fontWeight: ArFontWeight.book,
            ).copyWith(
              fontFamily: _showHtml ? null : 'Courier New',
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(dynamic colors, dynamic typography) {
    final fileNameWithoutExtension =
        getBasenameWithoutExtension(filePath: widget.state.filename);

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
                  'EMAIL MESSAGE',
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
                tooltip: 'Copy email text',
                onPressed: _copyEmailToClipboard,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  widget.isFullScreen
                      ? Icons.fullscreen_exit_outlined
                      : Icons.fullscreen_outlined,
                  size: 24,
                ),
                tooltip: widget.isFullScreen ? 'Exit fullscreen' : 'Expand',
                onPressed: _toggleFullScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    if (dateString.isEmpty) return 'Unknown date';

    try {
      // Try parsing common email date formats
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy hh:mm a').format(date);
    } catch (e) {
      // Return as-is if parsing fails
      return dateString;
    }
  }
}

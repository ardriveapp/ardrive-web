import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/pages/drive_detail/components/document_preview_widget.dart';
import 'package:ardrive/pages/drive_detail/components/email_attachment_list.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

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

  /// The header names stay the email's own (From, To, Subject), since this
  /// is the message as text.
  Future<void> _copyEmailToClipboard() {
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

    return copyPreviewText(context, buffer.toString());
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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      children: [
        // Content area
        Expanded(
          child: Stack(
            children: [
              Container(
                color: widget.isFullScreen
                    ? colorTokens.containerL1
                    : colorTokens.containerRaised,
                child: ArDriveScrollBar(
                  controller: _scrollController,
                  alwaysVisible: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(ArDriveSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildEmailHeaders(colorTokens, typography),
                        const SizedBox(height: ArDriveSpacing.lg),
                        _buildEmailBody(colorTokens, typography),
                        if (widget.state.email.hasAttachments) ...[
                          const SizedBox(height: ArDriveSpacing.md),
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
                  bottom: ArDriveSpacing.md,
                  right: ArDriveSpacing.md,
                  child: ArDriveIconButton(
                    icon: ArDriveIcons.chevronUp(
                        size: 20, color: colorTokens.iconMid),
                    tooltip: appLocalizationsOf(context).previewScrollToTop,
                    onPressed: _scrollToTop,
                  ),
                ),
            ],
          ),
        ),
        // Bottom action bar
        _buildActionBar(colorTokens, typography),
      ],
    );
  }

  BoxDecoration _cardDecoration(ArDriveColorTokens colorTokens) =>
      BoxDecoration(
        color: colorTokens.containerL2,
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
        border: Border.all(color: colorTokens.strokeLow),
      );

  Widget _buildEmailHeaders(
    ArDriveColorTokens colorTokens,
    ArdriveTypographyNew typography,
  ) {
    final l10n = appLocalizationsOf(context);
    final email = widget.state.email;

    return Container(
      padding: const EdgeInsets.all(ArDriveSpacing.md),
      decoration: _cardDecoration(colorTokens),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject
          Text(
            email.subject,
            style: typography.heading6(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
          const SizedBox(height: ArDriveSpacing.md),
          Divider(color: colorTokens.strokeLow, height: 1),
          const SizedBox(height: ArDriveSpacing.md),
          _buildHeaderRow(
              l10n.emailPreviewFrom, email.from, colorTokens, typography),
          const SizedBox(height: ArDriveSpacing.xs),
          _buildHeaderRow(
              l10n.emailPreviewTo, email.to, colorTokens, typography),
          if (email.cc.isNotEmpty) ...[
            const SizedBox(height: ArDriveSpacing.xs),
            _buildHeaderRow(
                l10n.emailPreviewCc, email.cc, colorTokens, typography),
          ],
          const SizedBox(height: ArDriveSpacing.xs),
          _buildHeaderRow(
            l10n.emailPreviewDate,
            _formatDate(email.date),
            colorTokens,
            typography,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(
    String label,
    String value,
    ArDriveColorTokens colorTokens,
    ArdriveTypographyNew typography,
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
              color: colorTokens.textMid,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: typography.paragraphSmall(color: colorTokens.textHigh),
          ),
        ),
      ],
    );
  }

  Widget _buildViewToggle(
    ArDriveColorTokens colorTokens,
    ArdriveTypographyNew typography,
  ) {
    final l10n = appLocalizationsOf(context);

    return Container(
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
        border: Border.all(color: colorTokens.strokeMid),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            label: l10n.emailPreviewPlainText,
            isSelected: !_showHtml,
            onTap: () => setState(() => _showHtml = false),
            colorTokens: colorTokens,
            typography: typography,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(ArDriveRadius.sm),
            ),
          ),
          Container(width: 1, height: 32, color: colorTokens.strokeMid),
          _buildToggleButton(
            label: l10n.emailPreviewHtml,
            isSelected: _showHtml,
            onTap: () => setState(() => _showHtml = true),
            colorTokens: colorTokens,
            typography: typography,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(ArDriveRadius.sm),
            ),
          ),
        ],
      ),
    );
  }

  /// One side of the plain text / HTML switch. The chosen side is a tint,
  /// not the primary red it was: the switch is a view setting, not the
  /// page's call to action.
  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ArDriveColorTokens colorTokens,
    required ArdriveTypographyNew typography,
    required BorderRadius borderRadius,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        hoverColor: colorTokens.buttonSecondaryHover,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ArDriveSpacing.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? colorTokens.buttonSecondaryPress
                : Colors.transparent,
            borderRadius: borderRadius,
          ),
          child: Text(
            label,
            style: typography.paragraphSmall(
              color: isSelected ? colorTokens.textHigh : colorTokens.textMid,
              fontWeight:
                  isSelected ? ArFontWeight.semiBold : ArFontWeight.book,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailBody(
    ArDriveColorTokens colorTokens,
    ArdriveTypographyNew typography,
  ) {
    final hasHtmlBody = widget.state.email.hasHtmlBody;
    final hasTextBody = widget.state.email.textBody.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(ArDriveSpacing.md),
      decoration: _cardDecoration(colorTokens),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle between HTML and Text (if both available)
          if (hasHtmlBody && hasTextBody)
            Row(
              children: [
                Text(
                  appLocalizationsOf(context).emailPreviewViewAs,
                  style: typography.paragraphSmall(color: colorTokens.textMid),
                ),
                const SizedBox(width: ArDriveSpacing.sm),
                _buildViewToggle(colorTokens, typography),
              ],
            ),
          if (hasHtmlBody && hasTextBody)
            const SizedBox(height: ArDriveSpacing.md),
          // Body content
          SelectableText(
            _showHtml && hasHtmlBody
                ? widget.state.email.htmlBody
                : widget.state.email.textBody,
            style: typography
                .paragraphSmall(
                  fontWeight: ArFontWeight.book,
                  color: colorTokens.textHigh,
                )
                .copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(
    ArDriveColorTokens colorTokens,
    ArdriveTypographyNew typography,
  ) {
    final l10n = appLocalizationsOf(context);
    final fileNameWithoutExtension =
        getBasenameWithoutExtension(filePath: widget.state.filename);

    return Container(
      padding: const EdgeInsets.all(ArDriveSpacing.lg),
      color: widget.isFullScreen
          ? colorTokens.containerL2
          : colorTokens.containerRaised,
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
                // The same case and colour as every other preview's type.
                Text(
                  l10n.emailPreviewFileType,
                  style: typography.paragraphLarge(color: colorTokens.textLow),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: l10n.previewCopyText,
                onPressed: _copyEmailToClipboard,
                icon: ArDriveIcons.copy(size: 20, color: colorTokens.iconMid),
              ),
              const SizedBox(width: ArDriveSpacing.xs),
              IconButton(
                tooltip: widget.isFullScreen ? l10n.collapse : l10n.expand,
                onPressed: _toggleFullScreen,
                color: colorTokens.iconMid,
                icon: Icon(
                  widget.isFullScreen
                      ? Icons.fullscreen_exit_outlined
                      : Icons.fullscreen_outlined,
                  size: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    if (dateString.isEmpty) {
      return appLocalizationsOf(context).emailPreviewUnknownDate;
    }

    try {
      // Try parsing common email date formats
      final date = DateTime.parse(dateString);
      return formatDateTime(date);
    } catch (e) {
      // Return as-is if parsing fails
      return dateString;
    }
  }
}

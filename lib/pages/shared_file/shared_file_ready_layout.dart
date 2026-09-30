import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The ready card's shape, for every page that shows one thing someone was
/// sent: the shared file page, and `/view/{txId}` for a bare transaction.
///
/// They were one design that had drifted into two. When the shared file page
/// was rebuilt around a preview pane, `/view` kept the old single column,
/// because the layout lived in private methods of the share page's ready view
/// and nothing else could reach it. This is that layout, taken out whole, so
/// both pages are the same card by construction rather than by care.
///
/// It owns the arrangement and nothing else. What goes in each slot - which
/// identity, which preview, which panel - stays with the page that knows its
/// own data, so this file has no idea what a revision or a transaction is.
class SharedFileReadyLayout extends StatelessWidget {
  const SharedFileReadyLayout({
    super.key,
    required this.isWide,
    required this.identity,
    required this.download,
    required this.infoPanel,
    required this.previewPane,
    this.inlinePreview,
    this.notices = const [],
    this.belowHeader = const [],
    this.previewPaneKey,
  });

  /// The gap between the two regions, and between the identity and Download
  /// in the header above them.
  static const double paneGutter = 24;

  /// The preview pane's height on the wide card.
  ///
  /// Reserved whether or not there is anything in it yet, which is the whole
  /// point of it: the file appears *in place*, with the download button exactly
  /// where it was. The info panel beside it takes the same height, so the two
  /// regions line up and a tab swap never resizes half the card.
  static const double previewPaneHeight = 420;

  /// Whether there is room for the preview pane. Decided by the page, from the
  /// screen size, so that the frame's width and this layout always agree.
  final bool isWide;

  /// What the thing is. The page builds it for the layout in use - the wide
  /// card shows the picture in the pane, not beside the name.
  final Widget identity;

  /// The one thing to do with it. Full width on a phone, its natural width in
  /// the wide card's header.
  final Widget download;

  /// Details, and whatever else the page has to say about the thing, given the
  /// height to hold to: the pane's on the wide card, and none on a phone, where
  /// the column already scrolls and a panel scrolling inside it would be a
  /// scroll within a scroll.
  final Widget Function(double? height) infoPanel;

  /// What fills the pane on the wide card. Centred; it is the page's job to
  /// make it fit, or to scroll when it cannot.
  final Widget previewPane;

  /// The preview on a phone, underneath Download, or null when there is
  /// nothing to show yet. There is no resting box on a phone - an empty band
  /// above the fold would cost more than it says.
  final Widget? inlinePreview;

  /// Anything that must be read before the file itself - a version notice -
  /// above everything else.
  final List<Widget> notices;

  /// A line that belongs to the header, under the identity and Download.
  final List<Widget> belowHeader;

  /// Lets a test find and measure the pane.
  final Key? previewPaneKey;

  @override
  Widget build(BuildContext context) =>
      isWide ? _buildWide(context) : _buildNarrow(context);

  /// The phone column, which is where most links are opened: identity,
  /// Download, an optional preview underneath it, then the details.
  Widget _buildNarrow(BuildContext context) {
    final inlinePreview = this.inlinePreview;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...notices,
        identity,
        const SizedBox(height: 20),
        download,
        ...belowHeader,
        if (inlinePreview != null) ...[
          const SizedBox(height: 16),
          inlinePreview,
        ],
        const SizedBox(height: 16),
        infoPanel(null),
      ],
    );
  }

  /// The desktop card: what it is and the one thing to do with it across the
  /// top, then the file itself beside what is known about it.
  ///
  /// Two things decide the shape. The Download button is the primary action and
  /// has to stay obvious, so it keeps the top of the reading order rather than
  /// being pushed under a preview; and the preview pane is *always* laid out,
  /// empty or not, so that the file arriving fills a hole that was already
  /// there instead of reflowing the card under the reader's cursor.
  ///
  /// Header first also means the visual order, the widget order and the tab
  /// order are the same one, so no focus traversal policy is needed to make
  /// the keyboard reach Download first.
  Widget _buildWide(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...notices,
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: identity),
            const SizedBox(width: paneGutter),
            download,
          ],
        ),
        ...belowHeader,
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                key: previewPaneKey,
                height: previewPaneHeight,
                decoration: BoxDecoration(
                  color: colors.themeBgCanvas,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.themeBorderDefault),
                ),
                clipBehavior: Clip.antiAlias,
                // Centred the way `DetailsPanel` centres the same widget.
                child: Center(child: previewPane),
              ),
            ),
            const SizedBox(width: paneGutter),
            Expanded(flex: 2, child: infoPanel(previewPaneHeight)),
          ],
        ),
      ],
    );
  }
}

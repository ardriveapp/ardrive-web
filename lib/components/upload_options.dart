import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The optional settings of an upload, behind one line that says what they
/// are set to. Most uploads leave them alone, and the line keeps them in view
/// without taking the room of the choice every upload needs: how to pay.
///
/// It holds the thumbnails choice itself, so the summary follows the box.
class UploadOptions extends StatefulWidget {
  const UploadOptions({
    super.key,
    required this.thumbnails,
    required this.onThumbnailsChanged,
    this.compress,
    this.onCompressChanged,
    required this.summary,
    required this.children,
  });

  /// Whether thumbnails will be made, or null when there are no images.
  final bool? thumbnails;
  final void Function(bool) onThumbnailsChanged;

  /// Whether text and code will be compressed, or null when the review does
  /// not offer it (a private drive, nothing it would compress).
  final bool? compress;
  final void Function(bool)? onCompressChanged;

  /// What the other options are set to, in a few words each.
  final List<String> summary;
  final List<Widget> children;

  @override
  State<UploadOptions> createState() => _UploadOptionsState();
}

class _UploadOptionsState extends State<UploadOptions> {
  bool _open = false;
  late bool? _thumbnails = widget.thumbnails;
  late bool? _compress = widget.compress;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);
    final summaryStyle = typography.paragraphSmall(
      fontWeight: ArFontWeight.semiBold,
      color: colorTokens.textLow,
    );

    final summary = [
      if (_thumbnails != null)
        _thumbnails! ? l10n.thumbnailsOn : l10n.thumbnailsOff,
      if (_compress ?? false) l10n.compressedSummary,
      ...widget.summary,
    ];

    // A dot drawn, not typed: in this font a typed one reads as a full stop.
    Widget separator() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: colorTokens.textLow,
              shape: BoxShape.circle,
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: ArDriveFocusable(
            onActivate: () => setState(() => _open = !_open),
            child: ArDriveClickArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = !_open),
                child: Row(
                  children: [
                    (_open
                        ? ArDriveIcons.carretDown
                        : ArDriveIcons.carretRight)(
                      size: 16,
                      color: colorTokens.textMid,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.uploadOptions,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colorTokens.textHigh,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Open, the options themselves say what is set.
                    if (!_open)
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (var i = 0; i < summary.length; i++) ...[
                              if (i > 0) separator(),
                              Text(summary[i], style: summaryStyle),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_thumbnails != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        ArDriveCheckBox(
                          title: l10n.uploadWithThumbnails,
                          useNewIcons: true,
                          checked: _thumbnails!,
                          titleStyle: typography.paragraphNormal(
                            fontWeight: ArFontWeight.semiBold,
                          ),
                          onChange: (value) {
                            setState(() => _thumbnails = value);
                            widget.onThumbnailsChanged(value);
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: ArDriveIconButton(
                            icon: ArDriveIcons.info(
                              size: 16,
                              color: colorTokens.textMid,
                            ),
                            tooltip: l10n.thumbnailsCostNote,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_compress != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CompressTextAndCodeRow(
                      value: _compress!,
                      onChanged: (value) {
                        setState(() => _compress = value);
                        widget.onCompressChanged?.call(value);
                      },
                    ),
                  ),
                for (final child in widget.children)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: child,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Compress text and code": a checkbox like the thumbnails one beside it,
/// since the choice applies when Upload is pressed, with what it means as a
/// caption under the label, lined up with the label rather than the box.
class CompressTextAndCodeRow extends StatelessWidget {
  const CompressTextAndCodeRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final void Function(bool) onChanged;

  /// The box and the gap the checkbox leaves before its label.
  static const double _labelIndent = 18.5 + 8;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArDriveCheckBox(
          title: l10n.compressTextAndCode,
          useNewIcons: true,
          checked: value,
          titleStyle: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
          ),
          onChange: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.only(left: _labelIndent),
          child: Text(
            l10n.compressTextAndCodeHint,
            style: typography.paragraphSmall(
              fontWeight: ArFontWeight.book,
              color: colorTokens.textMid,
            ),
          ),
        ),
      ],
    );
  }
}

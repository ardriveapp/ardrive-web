import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The optional settings of an upload, behind one line. Most uploads leave
/// them alone, so the line names a setting only when Upload is waiting on it,
/// and otherwise leaves the room to the choice every upload needs: how to pay.
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

  /// What Upload is waiting on in the options, in a few words each; empty
  /// when nothing is.
  final List<String> summary;
  final List<Widget> children;

  @override
  State<UploadOptions> createState() => _UploadOptionsState();
}

class _UploadOptionsState extends State<UploadOptions> {
  late bool? _thumbnails = widget.thumbnails;
  late bool? _compress = widget.compress;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);

    final groups = <Widget>[
      if (_thumbnails != null)
        Row(
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
            const SizedBox(width: ArDriveSpacing.xs),
            ArDriveIconButton(
              icon: ArDriveIcons.info(size: 16, color: colorTokens.textMid),
              tooltip: l10n.thumbnailsCostNote,
            ),
          ],
        ),
      if (_compress != null)
        CompressTextAndCodeRow(
          value: _compress!,
          onChanged: (value) {
            setState(() => _compress = value);
            widget.onCompressChanged?.call(value);
          },
        ),
      ...widget.children,
    ];

    return ArDriveDisclosure(
      icon: Icons.tune,
      title: l10n.uploadOptions,
      summary: widget.summary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: ArDriveSpacing.md),
            groups[i],
          ],
        ],
      ),
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

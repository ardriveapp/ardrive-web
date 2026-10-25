import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';

/// An ID, address or key, usually shortened, in Roboto Mono at its final
/// width from the first frame.
///
/// The face loads on demand, and until it arrives the text is drawn in the
/// narrower Wavehaus. Sized to Roboto Mono's width up front, whatever sits
/// beside it - a copy button, the rest of a sentence - stays where it is when
/// the face replaces the fallback.
///
/// [style] is a [ArdriveTypographyNew.code] style.
class ArDriveIdText extends StatelessWidget {
  const ArDriveIdText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  /// [text] with [id] in it drawn as an [ArDriveIdText], and the rest in the
  /// paragraph's own style: an address inside a sentence such as "By
  /// abc123...xyz9". Only the first [id] is set apart. When [text] doesn't
  /// hold [id], it is one plain span.
  static List<InlineSpan> spansIn(
    String text,
    String id, {
    required TextStyle idStyle,
  }) {
    final start = id.isEmpty ? -1 : text.indexOf(id);
    if (start < 0) return [TextSpan(text: text)];

    return [
      if (start > 0) TextSpan(text: text.substring(0, start)),
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: ArDriveIdText(id, style: idStyle),
      ),
      if (start + id.length < text.length)
        TextSpan(text: text.substring(start + id.length)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ArDriveMonospace.widthOf(
        text,
        style.fontSize ?? 13,
        textScaler:
            MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling,
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}

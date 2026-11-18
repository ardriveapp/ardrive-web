import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// One optional part of a dialog, folded to a single row that says what it
/// is set to: an upload's options, or the name to give it.
///
/// The row is an icon, a [title], a [summary] in a quieter style and a
/// chevron; pressing it, or Enter or Space on it, shows [child] under the
/// title. Rows of these line up with each other, so a dialog can stack them.
///
/// With [trailing] in place of a [child], the row is not folded at all: it
/// shows [trailing] at its end instead of the chevron, such as a link to
/// get the thing the row is about.
class ArDriveDisclosure extends StatefulWidget {
  const ArDriveDisclosure({
    super.key,
    required this.title,
    this.icon,
    this.summary = const [],
    this.child,
    this.trailing,
    this.initiallyOpen = false,
    this.onOpenChanged,
  }) : assert(child == null || trailing == null,
            'A row with a trailing widget does not fold');

  final String title;

  /// Drawn at [ArDriveDisclosure.iconSize] in the icon colour.
  final IconData? icon;

  /// What is set, in a few words each, separated by dots. Hidden while open,
  /// where the content says it.
  final List<String> summary;

  final Widget? child;
  final Widget? trailing;
  final bool initiallyOpen;
  final ValueChanged<bool>? onOpenChanged;

  static const double iconSize = 18;

  /// The row's height, the same as a menu item's.
  static const double rowHeight = 40;

  /// How far the content sits in, so it lines up with the title.
  static double contentIndentFor({required bool hasIcon}) =>
      hasIcon ? iconSize + ArDriveSpacing.xs : 0;

  @override
  State<ArDriveDisclosure> createState() => _ArDriveDisclosureState();
}

class _ArDriveDisclosureState extends State<ArDriveDisclosure> {
  late bool _open = widget.initiallyOpen;

  bool get _folds => widget.child != null;

  void _toggle() {
    setState(() => _open = !_open);
    widget.onOpenChanged?.call(_open);
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    const motion = Duration(milliseconds: 150);
    final summary = _open ? const <String>[] : widget.summary;

    // A dot drawn, not typed: in this font a typed one reads as a full stop.
    Widget dot() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: ArDriveSpacing.xs),
          child: Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: colorTokens.textLow,
              shape: BoxShape.circle,
            ),
          ),
        );

    final row = SizedBox(
      height: ArDriveDisclosure.rowHeight,
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: ArDriveDisclosure.iconSize,
              color: colorTokens.iconMid,
            ),
            const SizedBox(width: ArDriveSpacing.xs),
          ],
          // A short label, kept whole; the summary gives way instead.
          Text(
            widget.title,
            maxLines: 1,
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textHigh,
            ),
          ),
          const SizedBox(width: ArDriveSpacing.xs),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < summary.length; i++) ...[
                  if (i > 0) dot(),
                  Flexible(
                    child: Text(
                      summary[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typography.paragraphSmall(
                        fontWeight: ArFontWeight.semiBold,
                        color: colorTokens.textLow,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: ArDriveSpacing.xs),
            widget.trailing!,
          ] else if (_folds)
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: reduceMotion ? Duration.zero : motion,
              child: Icon(
                Icons.expand_more,
                size: 20,
                color: colorTokens.iconMid,
              ),
            ),
        ],
      ),
    );

    if (!_folds) {
      return Semantics(container: true, child: row);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: ArDriveFocusable(
            onActivate: _toggle,
            child: ArDriveClickArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: row,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: reduceMotion ? Duration.zero : motion,
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: _open
              ? Padding(
                  padding: EdgeInsets.only(
                    left: ArDriveDisclosure.contentIndentFor(
                      hasIcon: widget.icon != null,
                    ),
                    top: ArDriveSpacing.xxs,
                    bottom: ArDriveSpacing.xs,
                  ),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

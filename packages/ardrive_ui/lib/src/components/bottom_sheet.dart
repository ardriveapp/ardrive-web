import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Opens [builder]'s widget as a sheet from the bottom of the screen: the
/// phone form of a dialog. Build the sheet with [ArDriveBottomSheet] so its
/// title, spacing and actions match [ArDriveStandardModalNew].
Future<T?> showArDriveBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    useSafeArea: true,
    backgroundColor: colorTokens.containerL2,
    barrierColor: const Color(0x80000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ArDriveRadius.lg),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) => Padding(
      // Keeps the sheet above the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: builder(context),
    ),
  );
}

/// The contents of a bottom sheet: a handle, an optional title, the content
/// and optional actions, spaced like [ArDriveStandardModalNew].
///
/// The sheet is at most 85% of the screen's height. Taller content scrolls
/// under the title, above the actions.
class ArDriveBottomSheet extends StatelessWidget {
  const ArDriveBottomSheet({
    super.key,
    required this.content,
    this.title,
    this.actions,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: ArDriveSpacing.lg,
    ),
    this.fillsHeight = false,
  });

  final String? title;
  final Widget content;
  final List<ModalAction>? actions;

  /// The padding around [content]. Lists whose rows reach the sheet's edges
  /// pass zero.
  final EdgeInsets contentPadding;

  /// Whether the sheet takes its full height, with [content] filling what the
  /// title and actions leave. For content that scrolls itself, such as a list
  /// of results, which can't sit inside the sheet's own scroll view.
  final bool fillsHeight;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: fillsHeight
          ? BoxConstraints.tightFor(height: maxHeight)
          : BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: fillsHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(
                top: ArDriveSpacing.xs,
                bottom: ArDriveSpacing.md,
              ),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorTokens.strokeHigh,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ArDriveSpacing.lg,
                0,
                ArDriveSpacing.lg,
                ArDriveSpacing.md,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: typography.heading3(
                    color: colorTokens.textHigh,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
              ),
            ),
          if (fillsHeight)
            Expanded(
              child: Padding(padding: contentPadding, child: content),
            )
          else
            Flexible(
              child: ArDriveScrollArea(
                padding: contentPadding,
                child: content,
              ),
            ),
          if (actions != null && actions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ArDriveSpacing.lg,
                ArDriveSpacing.md,
                ArDriveSpacing.lg,
                0,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: ArDriveModalActions(actions: actions!),
              ),
            ),
          const SizedBox(height: ArDriveSpacing.lg),
        ],
      ),
    );
  }
}

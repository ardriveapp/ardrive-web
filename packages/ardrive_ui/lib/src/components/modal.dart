import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_ui/src/components/breakpoint_layout_builder.dart';
import 'package:flutter/material.dart';

/// Under the tablet breakpoint a dialog fills the width less this gutter on
/// each side: a phone gave it Flutter's 40, and with the 350 cap a standard
/// dialog was a 310 px card on a 390 px screen.
const double _phoneGutter = ArDriveSpacing.md;

bool _onPhone(BuildContext context) =>
    MediaQuery.of(context).size.width < TABLET;

/// A screen under 600 high keeps the dialog as it always was: no inset, and
/// the standard card's own width, so a 320 by 568 phone loses no room to a
/// gutter and a phone on its side doesn't stretch a dialog across 800 px.
bool _shortScreen(BuildContext context) =>
    MediaQuery.of(context).size.height < 600;

/// Whether the standard dialog fills the width less the gutter.
bool _fillsPhone(BuildContext context) =>
    _onPhone(context) && !_shortScreen(context);

/// The space around a dialog: [given], or on a phone the 16 px gutter.
EdgeInsets? _insetFor(BuildContext context, EdgeInsets? given) {
  if (_shortScreen(context)) {
    return const EdgeInsets.symmetric(horizontal: 0, vertical: 8);
  }
  if (_onPhone(context)) {
    return given ??
        const EdgeInsets.symmetric(horizontal: _phoneGutter, vertical: 24);
  }
  return given;
}

class ArDriveModalNew extends StatelessWidget {
  const ArDriveModalNew({
    super.key,
    required this.content,
    required this.constraints,
    this.contentPadding = const EdgeInsets.all(16),
    this.action,
    this.backgroundColor,
  });

  final Widget content;
  final BoxConstraints constraints;
  final EdgeInsets contentPadding;
  final ModalAction? action;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ConstrainedBox(
      constraints: constraints,
      child: ArDriveCard(
        contentPadding: EdgeInsets.zero,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: colorTokens.containerRed,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(modalBorderRadius),
                    topRight: Radius.circular(modalBorderRadius),
                  ),
                ),
              ),
            ),
            Padding(
              padding: contentPadding,
              child: content,
            ),
            if (action != null) ...[
              Padding(
                padding: const EdgeInsets.only(
                    left: 16, right: 16, bottom: 24, top: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: ArDriveButtonNew(
                        variant: ButtonVariant.primary,
                        text: action!.title,
                        onPressed: action!.action,
                        typography: ArDriveTypographyNew.of(context),
                        isDisabled: !action!.isEnable,
                      ),
                    ),
                  ],
                ),
              ),
            ]
          ],
        ),
        boxShadow: BoxShadowCard.shadow80,
        backgroundColor: backgroundColor ?? colorTokens.containerL3,
        borderRadius: modalBorderRadius,
      ),
    );
  }
}

class ModalAction {
  ModalAction({
    required this.action,
    required this.title,
    this.isEnable = true,
    this.customWidth,
    this.variant,
    this.isLoading = false,
  });

  /// An action that only closes the dialog, such as Cancel or Close. It is
  /// secondary even when it is the only action: red says "this does the
  /// thing", and closing does nothing. A lone Cancel used to be drawn as a red
  /// primary button.
  ModalAction.dismiss({
    required this.action,
    required this.title,
    this.customWidth,
  })  : isEnable = true,
        isLoading = false,
        variant = ButtonVariant.secondary;

  final String title;
  final dynamic Function() action;
  final bool isEnable;

  /// Draws a spinner in place of the title, and takes no press, while the
  /// action it started is still running. The button keeps its width, so
  /// nothing beside it moves.
  final bool isLoading;
  final double? customWidth;

  /// Overrides the variant [ArDriveStandardModalNew] picks from the action's
  /// position, where a lone action is primary.
  final ButtonVariant? variant;
}

/// [insetPadding] is the least space around the dialog, Flutter's 40 by 24
/// when not given. A dialog drawn to fill a phone less a 16 margin passes 16.
Future<void> showAnimatedDialog(
  BuildContext context, {
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  required Widget content,
  Color? barrierColor,
  EdgeInsets? insetPadding,
}) {
  return showGeneralDialog(
    context: context,
    barrierColor:
        barrierColor ?? ArDriveTheme.of(context).themeData.colorTokens.scrim,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, a1, a2, widget) {
      return Transform.scale(
        scale: a1.value,
        child: Opacity(
          opacity: a1.value,
          child: widget,
        ),
      );
    },
    barrierDismissible: barrierDismissible,
    barrierLabel: '',
    useRootNavigator: useRootNavigator,
    pageBuilder: (context, a1, a2) {
      return Dialog(
        insetPadding: _insetFor(context, insetPadding),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: content,
      );
    },
  );
}

Future<T?> showAnimatedDialogWithBuilder<T>(
  BuildContext context, {
  bool barrierDismissible = true,
  required WidgetBuilder builder,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor:
        barrierColor ?? ArDriveTheme.of(context).themeData.colorTokens.scrim,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, a1, a2, widget) {
      return Transform.scale(
        scale: a1.value,
        child: Opacity(
          opacity: a1.value,
          child: widget,
        ),
      );
    },
    barrierDismissible: barrierDismissible,
    barrierLabel: '',
    pageBuilder: (context, a1, a2) {
      return Dialog(
        insetPadding: _insetFor(context, null),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: builder(context),
      );
    },
  );
}

Future<void> showStandardDialog(
  BuildContext context, {
  required String title,
  required String description,
  List<ModalAction>? actions,
  bool barrierDismissible = true,
}) {
  return showAnimatedDialog(
    context,
    barrierDismissible: barrierDismissible,
    content: ArDriveStandardModalNew(
      description: description,
      title: title,
      actions: actions,
    ),
  );
}

class ArDriveStandardModalNew extends StatelessWidget {
  const ArDriveStandardModalNew({
    super.key,
    this.title,
    this.titleWidget,
    this.description,
    this.content,
    this.actions,
    this.width,
    this.hasCloseButton = false,
    this.close,
    this.closeLabel = 'Close',
    this.scrollableContent = false,
  });

  final String? title;

  /// A widget to display as the title. Takes precedence over [title].
  final Widget? titleWidget;

  final String? description;
  final List<ModalAction>? actions;
  final Widget? content;
  final double? width;
  final bool hasCloseButton;
  final Function()? close;

  /// What a screen reader calls the close button.
  final String closeLabel;

  VoidCallback _close(BuildContext context) => () {
        if (close != null) {
          close?.call();
        } else {
          Navigator.pop(context);
        }
      };

  /// When true, the modal is bounded to the viewport height and its title
  /// and content scroll above fixed actions, so the actions can never be
  /// pushed off-screen on short/mobile layouts.
  ///
  /// Opt-in: leaving it false preserves the previous unbounded layout, which
  /// some callers rely on for content that manages its own height (e.g. an
  /// [Expanded] or a [ListView]) and would break under a scroll view.
  final bool scrollableContent;

  @override
  Widget build(BuildContext context) {
    late double maxWidth;
    final deviceWidth = MediaQuery.of(context).size.width;

    final typography = ArDriveTypographyNew.of(context);

    if (deviceWidth < modalStandardMaxWidthSize) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = modalStandardMaxWidthSize;
    }

    final header = <Widget>[
      if (title != null || titleWidget != null) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: titleWidget ??
                  Text(
                    title!,
                    style: typography.heading3(
                      fontWeight: ArFontWeight.bold,
                    ),
                  ),
            ),
            if (hasCloseButton)
              // Named, so a screen reader says what it does; it was an
              // unlabelled icon.
              Semantics(
                container: true,
                button: true,
                label: closeLabel,
                excludeSemantics: true,
                onTap: _close(context),
                child: ArDriveFocusable(
                  onActivate: _close(context),
                  child: ArDriveClickArea(
                    child: GestureDetector(
                      onTap: _close(context),
                      child: const Align(
                        alignment: Alignment.centerRight,
                        child: ArDriveIcon(
                          icon: ArDriveIconsData.x,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              )
          ],
        ),
        const SizedBox(
          height: 24,
        ),
      ],
    ];
    final middle = <Widget>[
      if (content != null) ...[
        content!,
        // Scrolling, 16 of the 24 sits outside the scroll, above the
        // actions, so content scrolling under them never touches them.
        SizedBox(
          height: scrollableContent && actions != null ? 8 : 24,
        ),
      ],
      if (content == null) ...[
        if (description != null) ...[
          Text(
            description!,
            style: typography.paragraphNormal(
              color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
            ),
            textAlign: TextAlign.left,
          ),
        ],
      ],
    ];
    final footer = <Widget>[
      if (actions != null) ...[
        // Content already ends in 24 of space; a second 24 left a gap twice
        // the one between the title and the content.
        if (content == null)
          const SizedBox(
            height: 24,
          )
        else if (scrollableContent)
          const SizedBox(
            height: 16,
          ),
        Padding(
          // Scrolling, the modal has no side padding of its own, so the
          // scroll area's divider runs edge to edge.
          padding: scrollableContent
              ? const EdgeInsets.symmetric(horizontal: 24)
              : EdgeInsets.zero,
          child: Align(
            alignment: Alignment.bottomRight,
            child: ArDriveModalActions(actions: actions!),
          ),
        )
      ]
    ];

    // On a phone the dialog fills the width less the gutter, whatever width
    // it asked for (README, Dialogs).
    final phoneWidth = deviceWidth - 2 * _phoneGutter;
    return ArDriveModalNew(
      constraints: _fillsPhone(context)
          ? BoxConstraints(
              minHeight: 100,
              minWidth: phoneWidth,
              maxWidth: phoneWidth,
            )
          : BoxConstraints(
              minHeight: 100,
              maxWidth: width ?? maxWidth,
              minWidth: 250,
            ),
      contentPadding: scrollableContent
          ? const EdgeInsets.symmetric(vertical: 16)
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      content: scrollableContent
          ? ConstrainedBox(
              // Bound the modal to most of the viewport and keep the actions
              // in view, scrolling the title and content above them, as
              // Flutter's own scrollable AlertDialog does. The actions used to
              // scroll away with the content, so a long form had to be
              // scrolled to its end to reach Next. The title scrolls too: at
              // the largest text on a short screen there is no room to hold
              // it as well.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Shows that it scrolls: a scrollbar in the right margin
                  // and a divider above the actions while more is below.
                  Flexible(
                    child: ArDriveScrollArea(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [...header, ...middle],
                      ),
                    ),
                  ),
                  ...footer,
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [...header, ...middle, ...footer],
            ),
    );
  }
}

/// A dialog's actions: right-aligned, 40 high, with the last one primary
/// unless an action sets its own variant. Shared by [ArDriveStandardModalNew]
/// and [ArDriveBottomSheet], so the two lay out their buttons the same way.
class ArDriveModalActions extends StatelessWidget {
  const ArDriveModalActions({super.key, required this.actions});

  final List<ModalAction> actions;

  static Widget? _loading(BuildContext context, ModalAction action) =>
      action.isLoading
          ? ArDriveSpinner(
              color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
            )
          : null;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    return Wrap(
      alignment: WrapAlignment.end,
      runSpacing: 8,
      children: [
        if (actions.isNotEmpty)
          ArDriveButtonNew(
            maxWidth: actions[0].customWidth ??
                ArDriveButtonNew.fittedWidth(context, actions[0].title,
                    minWidth: 100),
            typography: typography,
            variant: actions[0].variant ??
                (actions.length > 1
                    ? ButtonVariant.secondary
                    : ButtonVariant.primary),
            isDisabled: !actions[0].isEnable || actions[0].isLoading,
            customContent: _loading(context, actions[0]),
            text: actions.first.title,
            onPressed: actions.first.action,
          ),
        if (actions.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ArDriveButtonNew(
              maxWidth: actions[1].customWidth ??
                  ArDriveButtonNew.fittedWidth(context, actions[1].title,
                      minWidth: 110),
              variant: actions[1].variant ??
                  (actions.length > 2
                      ? ButtonVariant.secondary
                      : ButtonVariant.primary),
              isDisabled: !actions[1].isEnable || actions[1].isLoading,
              customContent: _loading(context, actions[1]),
              text: actions[1].title,
              onPressed: actions[1].action,
              typography: typography,
            ),
          ),
        // Sized and styled like the other two. It had no width limit, so it
        // wrapped onto a full-width row of its own, in a smaller font.
        if (actions.length > 2)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ArDriveButtonNew(
              typography: typography,
              variant: actions[2].variant ?? ButtonVariant.primary,
              maxWidth: actions[2].customWidth ??
                  ArDriveButtonNew.fittedWidth(context, actions[2].title,
                      minWidth: 110),
              isDisabled: !actions[2].isEnable || actions[2].isLoading,
              customContent: _loading(context, actions[2]),
              text: actions[2].title,
              onPressed: actions[2].action,
            ),
          ),
      ],
    );
  }
}

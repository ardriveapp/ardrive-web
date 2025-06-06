import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class ArDriveModal extends StatelessWidget {
  const ArDriveModal({
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
    return ConstrainedBox(
      constraints: constraints,
      child: ArDriveCard(
        contentPadding: contentPadding,
        content: content,
        boxShadow: BoxShadowCard.shadow80,
        backgroundColor: backgroundColor,
      ),
    );
  }
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
                        maxHeight: 40,
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

class ArDriveIconModal extends StatelessWidget {
  const ArDriveIconModal({
    super.key,
    required this.icon,
    required this.title,
    required this.content,
    this.actions,
  });

  final Widget icon;
  final String title;
  final String content;
  final List<ModalAction>? actions;

  @override
  Widget build(BuildContext context) {
    late double maxWidth;
    final deviceWidth = MediaQuery.of(context).size.width;

    if (deviceWidth < modalIconMaxWidthSize) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = modalIconMaxWidthSize;
    }

    return ArDriveModal(
      constraints: BoxConstraints(maxWidth: maxWidth),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Align(
              alignment: Alignment.centerRight,
              child: ArDriveIcon(
                icon: ArDriveIconsData.x,
              ),
            ),
          ),
          const SizedBox(
            height: 18,
          ),
          icon,
          Text(
            title,
            style: ArDriveTypography.headline.headline4Bold(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(
            height: 18,
          ),
          Text(
            content,
            style: ArDriveTypography.body.smallRegular(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(
            height: 32,
          ),
          if (actions != null && actions!.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ArDriveButton(
                  maxHeight: buttonActionHeight,
                  style: ArDriveButtonStyle.secondary,
                  backgroundColor:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                  fontStyle: ArDriveTypography.body
                      .buttonNormalBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      )
                      .copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  text: actions!.first.title,
                  onPressed: actions!.first.action,
                ),
                if (actions != null && actions!.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: ArDriveButton(
                      maxHeight: buttonActionHeight,
                      backgroundColor: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                      fontStyle: ArDriveTypography.body
                          .buttonNormalBold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeAccentSubtle,
                          )
                          .copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      text: actions![1].title,
                      onPressed: actions![1].action,
                    ),
                  ),
                const SizedBox(
                  height: 32,
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }
}

class ArDriveLongModal extends StatelessWidget {
  const ArDriveLongModal({
    super.key,
    required this.title,
    required this.content,
    this.action,
  });

  final String title;
  final String content;
  final ModalAction? action;

  @override
  Widget build(BuildContext context) {
    late double maxWidth;
    final deviceWidth = MediaQuery.of(context).size.width;

    if (deviceWidth < modalLongMaxWidthSize) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = modalLongMaxWidthSize;
    }
    return ArDriveModal(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: ArDriveTypography.headline.headline5Bold(),
                ),
                Text(
                  content,
                  style: ArDriveTypography.body.smallRegular(),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            ArDriveButton(
              maxHeight: buttonActionHeight,
              text: action!.title,
              onPressed: action!.action,
              fontStyle: ArDriveTypography.body.buttonLargeBold(),
            ),
            const SizedBox(
              width: 24,
            ),
          ],
          const _ModalCloseButton(),
        ],
      ),
      constraints: BoxConstraints(
        maxWidth: maxWidth,
      ),
    );
  }
}

class ArDriveMiniModal extends StatelessWidget {
  const ArDriveMiniModal({
    super.key,
    required this.title,
    required this.content,
    this.leading,
  });

  final String title;
  final String content;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    late double maxWidth;
    final deviceWidth = MediaQuery.of(context).size.width;

    if (deviceWidth < modalMiniMaxWidthSize) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = modalMiniMaxWidthSize;
    }

    return ArDriveModal(
      constraints: BoxConstraints(
        minHeight: 100,
        maxWidth: maxWidth,
        minWidth: 250,
      ),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(
              width: 16,
            )
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    title,
                    style: ArDriveTypography.body.smallBold(),
                  ),
                ),
                Flexible(
                  child: Text(
                    content,
                    style: ArDriveTypography.body.captionRegular(),
                  ),
                ),
              ],
            ),
          ),
          const _ModalCloseButton(),
        ],
      ),
    );
  }
}

class _ModalCloseButton extends StatelessWidget {
  const _ModalCloseButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
      },
      child: const ArDriveIcon(icon: ArDriveIconsData.close_circle),
    );
  }
}

class ArDriveStandardModal extends StatelessWidget {
  const ArDriveStandardModal({
    super.key,
    this.title,
    this.description,
    this.content,
    this.actions,
    this.width,
    this.hasCloseButton = false,
  });

  final String? title;
  final String? description;
  final List<ModalAction>? actions;
  final Widget? content;
  final double? width;
  final bool hasCloseButton;

  @override
  Widget build(BuildContext context) {
    late double maxWidth;
    final deviceWidth = MediaQuery.of(context).size.width;

    if (deviceWidth < modalStandardMaxWidthSize) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = modalStandardMaxWidthSize;
    }

    return ArDriveModal(
      constraints: BoxConstraints(
        minHeight: 100,
        maxWidth: width ?? maxWidth,
        minWidth: 250,
      ),
      content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      title!,
                      style: ArDriveTypography.headline.headline5Bold(),
                    ),
                  ),
                  if (hasCloseButton)
                    ArDriveClickArea(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: ArDriveIcon(
                            icon: ArDriveIconsData.x,
                            size: 24,
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
            if (content != null) ...[
              content!,
              const SizedBox(
                height: 24,
              ),
            ],
            if (content == null) ...[
              if (description != null) ...[
                Text(
                  description!,
                  style: ArDriveTypography.body.smallRegular(),
                  textAlign: TextAlign.left,
                ),
              ],
            ],
            if (actions != null) ...[
              const SizedBox(
                height: 24,
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: _buildActions(
                  actions!,
                  context,
                ),
              )
            ]
          ]),
    );
  }

  Widget _buildActions(List<ModalAction> actions, BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      runSpacing: 8,
      children: [
        if (actions.isNotEmpty)
          ArDriveButton(
            maxHeight: buttonActionHeight,
            style: ArDriveButtonStyle.secondary,
            maxWidth: actions[0].customWidth,
            backgroundColor:
                ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            fontStyle: ArDriveTypography.body
                .buttonNormalBold(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                )
                .copyWith(
                  fontWeight: FontWeight.w700,
                ),
            text: actions.first.title,
            onPressed: actions.first.action,
          ),
        if (actions.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ArDriveButton(
              style: actions.length > 2
                  ? ArDriveButtonStyle.secondary
                  : ArDriveButtonStyle.primary,
              maxHeight: buttonActionHeight,
              maxWidth: actions[0].customWidth,
              backgroundColor:
                  ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              fontStyle: ArDriveTypography.body
                  .buttonNormalRegular(
                    color: actions.length > 2
                        ? ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault
                        : ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeAccentSubtle,
                  )
                  .copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              isDisabled: !actions[1].isEnable,
              text: actions[1].title,
              onPressed: actions[1].action,
            ),
          ),
        if (actions.length > 2)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ArDriveButton(
              style: ArDriveButtonStyle.secondary,
              maxHeight: buttonActionHeight,
              backgroundColor:
                  ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              fontStyle: ArDriveTypography.body
                  .buttonNormalRegular(
                    color: actions.length > 2
                        ? ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault
                        : ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeAccentSubtle,
                  )
                  .copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              isDisabled: !actions[2].isEnable,
              text: actions[2].title,
              onPressed: actions[2].action,
            ),
          ),
      ],
    );
  }
}

class ModalAction {
  ModalAction({
    required this.action,
    required this.title,
    this.isEnable = true,
    this.customWidth,
    this.customHeight,
  });

  final String title;
  final dynamic Function() action;
  final bool isEnable;
  final double? customWidth;
  final double? customHeight;
}

Future<void> showAnimatedDialog(
  BuildContext context, {
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  required Widget content,
  Color? barrierColor,
}) {
  final lowScreenWarning = MediaQuery.of(context).size.height < 600;

  return showGeneralDialog(
    context: context,
    barrierColor: barrierColor ?? const Color(0x80000000),
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
        insetPadding: lowScreenWarning
            ? const EdgeInsets.symmetric(horizontal: 0, vertical: 8)
            : null,
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
  final lowScreenWarning = MediaQuery.of(context).size.height < 600;

  return showGeneralDialog<T>(
    context: context,
    barrierColor: barrierColor ?? const Color(0x80000000),
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
        insetPadding: lowScreenWarning
            ? const EdgeInsets.symmetric(horizontal: 0, vertical: 8)
            : null,
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: builder(context),
      );
    },
  );
}

Future<void> showLongModal(
  BuildContext context, {
  required String title,
  required String content,
  ModalAction? action,
}) {
  return showAnimatedDialog(
    context,
    content: ArDriveLongModal(
      title: title,
      content: content,
      action: action,
    ),
  );
}

Future<void> showStandardDialog(
  BuildContext context, {
  required String title,
  required String description,
  List<ModalAction>? actions,
  bool barrierDismissible = true,
  bool useNewArDriveUI = false,
}) {
  return showAnimatedDialog(
    context,
    barrierDismissible: barrierDismissible,
    content: useNewArDriveUI
        ? ArDriveStandardModalNew(
            description: description,
            title: title,
            actions: actions,
          )
        : ArDriveStandardModal(
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
    this.description,
    this.content,
    this.actions,
    this.width,
    this.hasCloseButton = false,
    this.close,
  });

  final String? title;
  final String? description;
  final List<ModalAction>? actions;
  final Widget? content;
  final double? width;
  final bool hasCloseButton;
  final Function()? close;

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

    return ArDriveModalNew(
      constraints: BoxConstraints(
        minHeight: 100,
        maxWidth: width ?? maxWidth,
        minWidth: 250,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      title!,
                      style: typography.heading3(
                        fontWeight: ArFontWeight.bold,
                      ),
                    ),
                  ),
                  if (hasCloseButton)
                    ArDriveClickArea(
                      child: GestureDetector(
                        onTap: () {
                          if (close != null) {
                            close?.call();
                          } else {
                            Navigator.pop(context);
                          }
                        },
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: ArDriveIcon(
                            icon: ArDriveIconsData.x,
                            size: 24,
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
            if (content != null) ...[
              content!,
              const SizedBox(
                height: 24,
              ),
            ],
            if (content == null) ...[
              if (description != null) ...[
                Text(
                  description!,
                  style: ArDriveTypography.body.smallRegular(),
                  textAlign: TextAlign.left,
                ),
              ],
            ],
            if (actions != null) ...[
              const SizedBox(
                height: 24,
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: _buildActions(
                  actions!,
                  context,
                ),
              )
            ]
          ]),
    );
  }

  Widget _buildActions(List<ModalAction> actions, BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    return Wrap(
      alignment: WrapAlignment.end,
      runSpacing: 8,
      children: [
        if (actions.isNotEmpty)
          ArDriveButtonNew(
            maxHeight: actions[0].customHeight ?? 40,
            maxWidth: actions[0].customWidth ?? 100,
            typography: typography,
            variant: actions.length > 1
                ? ButtonVariant.secondary
                : ButtonVariant.primary,
            text: actions.first.title,
            onPressed: actions.first.action,
          ),
        if (actions.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ArDriveButtonNew(
              maxHeight: actions[1].customHeight ?? 40,
              maxWidth: actions[1].customWidth ?? 110,
              variant: actions.length > 2
                  ? ButtonVariant.secondary
                  : ButtonVariant.primary,
              isDisabled: !actions[1].isEnable,
              text: actions[1].title,
              onPressed: actions[1].action,
              typography: typography,
            ),
          ),
        if (actions.length > 2)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ArDriveButtonNew(
              typography: typography,
              variant: ButtonVariant.primary,
              maxHeight: 40,
              fontStyle: ArDriveTypography.body
                  .buttonNormalRegular(
                    color: actions.length > 2
                        ? ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault
                        : ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeAccentSubtle,
                  )
                  .copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              isDisabled: !actions[2].isEnable,
              text: actions[2].title,
              onPressed: actions[2].action,
            ),
          ),
      ],
    );
  }
}

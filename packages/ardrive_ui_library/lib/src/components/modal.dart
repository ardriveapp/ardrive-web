import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

class ArDriveModal extends StatelessWidget {
  const ArDriveModal({
    super.key,
    required this.content,
    required this.constraints,
    this.contentPadding = const EdgeInsets.all(16),
  });

  final Widget content;
  final BoxConstraints constraints;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: constraints,
      child: ArDriveCard(
        content: Padding(
          padding: contentPadding,
          child: content,
        ),
        boxShadow: BoxShadowCard.shadow80,
      ),
    );
  }
}

class ArDriveLongModal extends StatelessWidget {
  const ArDriveLongModal({
    super.key,
    required this.title,
    required this.content,
    this.leading,
    this.action,
  });

  final String title;
  final String content;
  final Widget? leading;
  final ModalAction? action;

  @override
  Widget build(BuildContext context) {
    late double maxWidth;
    final deviceWidth = MediaQuery.of(context).size.width;

    if (deviceWidth < 583) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = 583;
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
            // TODO(@thiagocarvalhodev): use correct font here
            ArDriveButton(
              maxHeight: 32,
              text: action!.title,
              onPressed: action!.action,
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

    if (deviceWidth < 350) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = 350;
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
      child: ArDriveIcons.closeIcon(),
    );
  }
}

class ArDriveStandardModal extends StatelessWidget {
  const ArDriveStandardModal({
    super.key,
    required this.title,
    required this.content,
    this.actions,
  });

  final String title;
  final String content;
  final List<ModalAction>? actions;

  @override
  Widget build(BuildContext context) {
    late double maxWidth;
    final deviceWidth = MediaQuery.of(context).size.width;

    if (deviceWidth < 350) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = 350;
    }

    return ArDriveModal(
      constraints: BoxConstraints(
        minHeight: 100,
        maxWidth: maxWidth,
        minWidth: 250,
      ),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
          alignment: Alignment.topLeft,
          child: Text(
            title,
            style: ArDriveTypography.headline.headline4Bold(),
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Text(
          content,
          style: ArDriveTypography.body.smallRegular(),
        ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actions.isNotEmpty)
          ArDriveButton(
            maxHeight: 32,
            style: ArDriveButtonStyle.secondary,
            backgroundColor:
                ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            fontStyle: ArDriveTypography.body.buttonNormalRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
            text: actions.first.title,
            onPressed: actions.first.action,
          ),
        if (actions.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ArDriveButton(
              maxHeight: 32,
              backgroundColor:
                  ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              fontStyle: ArDriveTypography.body.buttonNormalRegular(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeAccentSubtle,
              ),
              text: actions[1].title,
              onPressed: actions[1].action,
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
  });

  final String title;
  final dynamic Function() action;
}

Future<void> showAnimatedDialog(
  BuildContext context, {
  bool barrierDismissible = true,
  required Widget content,
}) {
  return showGeneralDialog(
    context: context,
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
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: content,
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
  required String content,
  List<ModalAction>? actions,
  bool barrierDismissible = true,
}) {
  return showAnimatedDialog(
    context,
    barrierDismissible: barrierDismissible,
    content: ArDriveStandardModal(
      content: content,
      title: title,
      actions: actions,
    ),
  );
}

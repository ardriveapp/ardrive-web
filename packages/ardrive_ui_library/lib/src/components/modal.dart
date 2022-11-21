import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

class ArDriveModal extends StatelessWidget {
  const ArDriveModal({
    super.key,
    required this.content,
    required this.constraints,
  });

  final Widget content;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: constraints,
      child: ArDriveCard(
        content: content,
        boxShadow: BoxShadowCard.shadow80,
      ),
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

    if (deviceWidth < 305) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = 305;
    }

    return ArDriveModal(
      constraints: BoxConstraints(
        // maxHeight: 300,
        minHeight: 100,
        maxWidth: maxWidth,
        minWidth: 250,
      ),
      content: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            style: ArDriveTypography.body.xSmallBold(),
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
      ),
    );
  }

  Widget _buildActions(List<ModalAction> actions, BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actions.isNotEmpty)
          ArDriveButton(
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

Future<void> showStandardDialog(
  BuildContext context, {
  required String title,
  required String content,
  List<ModalAction>? actions,
  bool barrierDismissible = true,
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
        child: ArDriveStandardModal(
          content: content,
          title: title,
          actions: actions,
        ),
      );
    },
  );
}

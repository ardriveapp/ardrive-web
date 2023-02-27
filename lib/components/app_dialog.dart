import 'dart:async';

import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';

class AppDialog extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry contentPadding;
  final Widget content;
  final List<Widget> actions;
  final FutureOr<void> Function()? onWillPopCallback;

  final bool dismissable;
  static const double dialogBorderRadius = 4.0;
  static const double actionButtonsPadding = 16.0;
  static const EdgeInsets dialogContentPadding = EdgeInsets.symmetric(
    vertical: 12.0,
    horizontal: 18.0,
  );

  const AppDialog({
    required this.title,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 20, 24, 24),
    required this.content,
    this.onWillPopCallback,
    this.actions = const [],
    this.dismissable = true,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => WillPopScope(
        onWillPop: () async {
          await onWillPopCallback?.call();
          return dismissable;
        },
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogBorderRadius)),
          titlePadding: EdgeInsets.zero,
          title: Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(dialogBorderRadius),
                topRight: Radius.circular(dialogBorderRadius),
              ),
              color: kDarkSurfaceColor,
            ),
            height: 64,
            child: Padding(
              padding: dialogContentPadding,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .headline6!
                            .copyWith(color: kOnDarkSurfaceHighEmphasis),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          contentPadding: contentPadding,
          content: content,
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: actionButtonsPadding,
            vertical: actionButtonsPadding,
          ),
          actions: actions,
        ),
      );
}

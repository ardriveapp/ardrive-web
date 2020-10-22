import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';

class AppDialog extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry contentPadding;
  final Widget content;
  final List<Widget> actions;

  final bool dismissable;

  const AppDialog({
    this.title,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 20, 24, 24),
    this.content,
    this.actions,
    this.dismissable = true,
  });

  @override
  Widget build(BuildContext context) => WillPopScope(
        onWillPop: () async => dismissable,
        child: AlertDialog(
          titlePadding: EdgeInsets.zero,
          title: Container(
            color: kDarkColor,
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .headline6
                          .copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          contentPadding: contentPadding,
          content: content,
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          actions: actions,
        ),
      );
}

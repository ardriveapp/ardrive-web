import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';

class AppDialog extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry contentPadding;
  final Widget content;
  final List<Widget> actions;

  const AppDialog({
    this.title,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 20, 24, 24),
    this.content,
    this.actions,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
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
                        .bodyText1
                        .copyWith(color: Colors.white, letterSpacing: 2),
                  ),
                  IconButton(
                      icon: Icon(
                        Icons.close,
                        color: kOnDarkMediumEmphasis,
                      ),
                      onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          ),
        ),
        contentPadding: contentPadding,
        content: content,
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0),
        actions: actions,
      );
}

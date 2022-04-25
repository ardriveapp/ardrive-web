import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';

import 'components.dart';

Future<void> showProgressDialog(BuildContext context, String title) =>
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => ProgressDialog(title: title),
    );

class ProgressDialog extends StatelessWidget {
  final String title;
  final Widget? details;
  final Widget? progressBar;

  ProgressDialog({required this.title, this.progressBar, this.details});

  @override
  Widget build(BuildContext context) => AppDialog(
        dismissable: false,
        title: title,
        content: SizedBox(
          width: kSmallDialogWidth + 100,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(
                  child: SizedBox(
                      width: 74,
                      height: 74,
                      child: CircularProgressIndicator(
                        strokeWidth: 8,
                      ))),
              SizedBox(
                height: 34,
              ),
              if (progressBar != null) progressBar!,
              SizedBox(
                height: 24,
              ),
              if (details != null) details!,
            ],
          ),
        ),
      );
}

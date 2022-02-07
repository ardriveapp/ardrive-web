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
  final Widget? child;
  ProgressDialog({required this.title, this.child});

  @override
  Widget build(BuildContext context) => AppDialog(
        dismissable: false,
        title: title,
        content: SizedBox(
          width: kMediumDialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(child: CircularProgressIndicator()),
              child ?? Container(),
            ],
          ),
        ),
      );
}

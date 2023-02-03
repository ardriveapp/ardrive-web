import 'dart:async';

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
  final Widget? percentageDetails;
  final Widget? progressDescription;
  final Widget? progressBar;
  final FutureOr<void> Function()? onDismiss;

  const ProgressDialog({
    Key? key,
    required this.title,
    this.progressBar,
    this.progressDescription,
    this.percentageDetails,
    this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => AppDialog(
        dismissable: onDismiss != null,
        onWillPopCallback: onDismiss,
        title: title,
        content: SizedBox(
          width: kSmallDialogWidth + 164,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: SizedBox(
                    width: 74,
                    height: 74,
                    child: CircularProgressIndicator(
                      strokeWidth: 8,
                    )),
              ),
              if (progressDescription != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: progressDescription!,
                ),
              if (progressBar != null) progressBar!,
              if (percentageDetails != null)
                Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: percentageDetails!),
            ],
          ),
        ),
      );
}

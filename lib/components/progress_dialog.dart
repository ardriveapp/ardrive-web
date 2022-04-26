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
  final Widget? details;
  final Widget? progressBar;

  ProgressDialog(
      {required this.title,
      this.progressBar,
      this.details,
      this.percentageDetails});

  @override
  Widget build(BuildContext context) => AppDialog(
        dismissable: false,
        title: title,
        content: SizedBox(
          width: kSmallDialogWidth + 164,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: const SizedBox(
                    width: 74,
                    height: 74,
                    child: CircularProgressIndicator(
                      strokeWidth: 8,
                    )),
              ),
              if (details != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: details!,
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

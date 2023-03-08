import 'dart:async';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

Future<void> showProgressDialog(
  BuildContext context, {
  required String title,
  List<ModalAction>? actions,
}) =>
    showAnimatedDialog(
      context,
      barrierDismissible: false,
      content: ProgressDialog(
        title: title,
        actions: actions ?? const [],
      ),
    );

class ProgressDialog extends StatelessWidget {
  const ProgressDialog({
    super.key,
    required this.title,
    this.actions = const [],
    this.progressDescription,
    this.progressBar,
    this.percentageDetails,
  });

  final String title;
  final List<ModalAction> actions;
  final Widget? progressDescription;
  final Widget? progressBar;
  final Widget? percentageDetails;

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModal(
      title: title,
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
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
}

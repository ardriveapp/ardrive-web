import 'dart:async';

import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

Future<void> showProgressDialog(
  BuildContext context, {
  required String title,
  List<ModalAction>? actions,
  bool useNewArDriveUI = false,
}) =>
    showArDriveDialog(
      context,
      barrierDismissible: false,
      content: ProgressDialog(
        title: title,
        actions: actions ?? const [],
        useNewArDriveUI: useNewArDriveUI,
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
    this.useNewArDriveUI = false,
  });

  final String title;
  final List<ModalAction> actions;
  final Widget? progressDescription;
  final Widget? progressBar;
  final Widget? percentageDetails;
  final bool useNewArDriveUI;
  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: SizedBox(
                width: 74,
                height: 74,
                child: CircularProgressIndicator(
                  strokeWidth: 8,
                ),
              ),
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

    if (useNewArDriveUI) {
      return ArDriveStandardModalNew(
        title: title,
        content: content,
        actions: actions,
      );
    }

    return ArDriveStandardModal(
      title: title,
      content: content,
      actions: actions,
    );
  }
}

import 'dart:async';

import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

Future<void> showProgressDialog(
  BuildContext context, {
  required String title,
  List<ModalAction>? actions,
}) =>
    showArDriveDialog(
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
    this.title,
    this.titleWidget,
    this.actions = const [],
    this.progressDescription,
    this.progressBar,
    this.percentageDetails,
  })  : assert(title != null || titleWidget != null,
            'Either title or titleWidget must be provided'),
        assert(!(title != null && titleWidget != null),
            'Provide only one of title or titleWidget, not both');

  /// The title text. Must not be provided if [titleWidget] is provided.
  final String? title;

  /// A widget to display as the title. Must not be provided if [title] is provided.
  final Widget? titleWidget;

  final List<ModalAction> actions;
  final Widget? progressDescription;
  final Widget? progressBar;
  final Widget? percentageDetails;

  @override
  Widget build(BuildContext context) {
    // The design system's spinner, as every other wait in the app shows:
    // it was a 75 px Lottie loader.
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.lg),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArDriveSpinner(size: ArDriveSpinnerSize.large),
            if (progressDescription != null)
              Padding(
                padding: const EdgeInsets.only(top: ArDriveSpacing.md),
                child: progressDescription!,
              ),
            if (progressBar != null)
              Padding(
                padding: const EdgeInsets.only(top: ArDriveSpacing.md),
                child: progressBar!,
              ),
            if (percentageDetails != null)
              Padding(
                padding: const EdgeInsets.only(top: ArDriveSpacing.md),
                child: percentageDetails!,
              ),
          ],
        ),
      ),
    );

    return ArDriveStandardModalNew(
      // title and titleWidget are mutually exclusive per constructor assertion
      title: title,
      titleWidget: titleWidget,
      content: content,
      actions: actions,
    );
  }
}

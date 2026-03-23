import 'dart:async';

import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

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
    this.title,
    this.titleWidget,
    this.actions = const [],
    this.progressDescription,
    this.progressBar,
    this.percentageDetails,
    this.useNewArDriveUI = false,
  }) : assert(title != null || titleWidget != null,
            'Either title or titleWidget must be provided');

  /// The title text. If [titleWidget] is provided, this is ignored.
  final String? title;

  /// A widget to display as the title. Takes precedence over [title].
  final Widget? titleWidget;

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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: LottieBuilder.asset(
                Resources.images.login.ardriveLoader,
                filterQuality: FilterQuality.high,
                frameRate: FrameRate.max,
                addRepaintBoundary: true,
                height: 75,
                width: 75,
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
        title: title ?? '',
        titleWidget: titleWidget,
        content: content,
        actions: actions,
      );
    }

    return ArDriveStandardModal(
      title: title ?? '',
      content: content,
      actions: actions,
    );
  }
}

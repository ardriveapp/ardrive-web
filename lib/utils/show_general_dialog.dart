import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showArDriveDialog(
  BuildContext context, {
  bool barrierDismissible = true,
  required Widget content,
  Color? barrierColor,
}) async {
  final activityTracker = context.read<ActivityTracker>();
  activityTracker.setShowingAnyDialog(true);
  return showAnimatedDialog(
    context,
    content: content,
    barrierColor: barrierColor,
    barrierDismissible: barrierDismissible,
  ).then((value) => activityTracker.setShowingAnyDialog(false));
}

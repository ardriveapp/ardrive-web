import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showArDriveDialog(
  BuildContext context, {
  bool barrierDismissible = true,
  bool useRootNavigator = true,
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
    useRootNavigator: useRootNavigator,
  ).whenComplete(() => activityTracker.setShowingAnyDialog(false));
}

/// [showArDriveDialog] for a dialog that answers: the dialog is built by
/// [builder] and the value it pops with is returned.
Future<T?> showArDriveDialogWithBuilder<T>(
  BuildContext context, {
  bool barrierDismissible = true,
  required WidgetBuilder builder,
}) {
  final activityTracker = context.read<ActivityTracker>();
  activityTracker.setShowingAnyDialog(true);
  return showAnimatedDialogWithBuilder<T>(
    context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  ).whenComplete(() => activityTracker.setShowingAnyDialog(false));
}

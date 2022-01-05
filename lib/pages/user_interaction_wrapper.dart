import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showModalDialog(
    BuildContext context, Future Function() showDialog) async {
  return context
      .read<ActivityCubit>()
      .performUninterruptableActivity(showDialog);
}

import 'package:ardrive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'congestion_warning_wrapper.dart';

Future<void> showUninterruptibleDialog(
  BuildContext context,
  Future Function() showDialog, {
  bool warnAboutCongestion = true,
}) async {
  context.read<ProfileCubit>().performUninterruptibleAction(
    () async {
      if (warnAboutCongestion) {
        return showCongestionWarning(context, showDialog);
      } else {
        return showDialog();
      }
    },
  );
}

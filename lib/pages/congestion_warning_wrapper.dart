import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showCongestionDependentModalDialog(
    BuildContext context, Function() showAppDialog) async {
  late bool warnAboutCongestion;

  try {
    final mempoolSize =
        await context.read<ArweaveService>().getMempoolSizeFromArweave();

    warnAboutCongestion = mempoolSize > mempoolWarningSizeLimit;
  } catch (e) {
    warnAboutCongestion = false;
  }

  return await showStandardDialog(context,
      title: appLocalizationsOf(context).warningEmphasized,
      content: appLocalizationsOf(context).congestionWarning,
      actions: [
        ModalAction(
          action: () {
            Navigator.of(context).pop(false);
          },
          title: appLocalizationsOf(context).tryLaterCongestionEmphasized,
        ),
        ModalAction(
          action: () {
            Navigator.of(context).pop(true);
            return showAppDialog();
          },
          title: appLocalizationsOf(context).proceedCongestionEmphasized,
        ),
      ]);
}

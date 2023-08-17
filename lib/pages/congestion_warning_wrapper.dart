import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
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

  // ignore: use_build_context_synchronously
  return await showModalDialog(context, () async {
    if (warnAboutCongestion) {
      bool shouldShowDialog = false;
      await showAnimatedDialog(
        context,
        content: ArDriveStandardModal(
          title: appLocalizationsOf(context).warningEmphasized,
          content: SizedBox(
            width: kMediumDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                                text: appLocalizationsOf(context)
                                    .congestionWarning),
                          ],
                          style: ArDriveTypography.body.buttonNormalRegular(),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          actions: [
            ModalAction(
              action: () {
                shouldShowDialog = false;
                Navigator.of(context).pop(false);
              },
              title: appLocalizationsOf(context).tryLaterCongestionEmphasized,
            ),
            ModalAction(
              action: () async {
                shouldShowDialog = true;
                Navigator.of(context).pop(true);
              },
              title: appLocalizationsOf(context).proceedEmphasized,
            ),
          ],
        ),
        barrierDismissible: false,
      );
      if (shouldShowDialog) {
        return showAppDialog();
      } else {
        return;
      }
    } else {
      return showAppDialog();
    }
  });
}

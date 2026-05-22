import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

void showLoaderDialog({required BuildContext context}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  PlausibleEventTracker.trackPageview(
    page: PlausiblePageView.generateWalletLoader,
  );
  showArDriveDialog(
    context,
    barrierDismissible: false,
    useRootNavigator: false,
    content: ArDriveLoginModal(
      width: 380,
      hasCloseButton: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LottieBuilder.asset(
            Resources.images.login.ardriveLoader,
            filterQuality: FilterQuality.high,
            frameRate: FrameRate.max,
            addRepaintBoundary: true,
            height: 75,
            width: 75,
          ),
          const SizedBox(height: 16),
          Text(
            'Generating wallet...',
            style: ArDriveTypographyNew.of(context).paragraphNormal(
                color: colorTokens.textLow,
                fontWeight: ArFontWeight.semiBold),
          ),
        ],
      ),
    ),
  );
}

void showBlockingMessageDialog(
    {required BuildContext context, required String message}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  showArDriveDialog(context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: ArDriveLoginModal(
        width: 380,
        hasCloseButton: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LottieBuilder.asset(
              Resources.images.login.ardriveLoader,
              filterQuality: FilterQuality.high,
              frameRate: FrameRate.max,
              addRepaintBoundary: true,
              height: 75,
              width: 75,
            ),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: ArDriveTypographyNew.of(context).paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold)),
          ],
        ),
      ));
}

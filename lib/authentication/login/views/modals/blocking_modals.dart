import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

void showLoaderDialog({required BuildContext context}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  showArDriveDialog(
    context,
    barrierDismissible: false,
    useRootNavigator: false,
    content: Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: colorTokens.containerL3,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 64, 64, 16),
            child: LottieBuilder.asset(
              Resources.images.login.ardriveLoader,
              filterQuality: FilterQuality.high,
              frameRate: FrameRate.max,
              addRepaintBoundary: true,
              height: 75,
              width: 75,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 64),
            child: Text(
              'Generating wallet...',
              style: ArDriveTypographyNew.of(context).paragraphLarge(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold),
            ),
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
      content: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: colorTokens.containerL3,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(64),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: ArDriveTypographyNew.of(context).paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
            ),
          ],
        ),
      ));
}

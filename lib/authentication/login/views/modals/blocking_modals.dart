import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

void showLoaderDialog({required BuildContext context}) {
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
              child: ArDriveImage(
                image: AssetImage(Resources.images.login.ardriveLoader),
                height: 75,
                width: 75,
              ),
            ),
          ],
        ),
      ));
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
                  style: ArDriveTypographyNew.desktop.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
            ),
          ],
        ),
      ));
}
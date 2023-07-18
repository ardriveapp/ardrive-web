import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TurboSuccessView extends StatelessWidget {
  const TurboSuccessView({super.key});

  @override
  Widget build(BuildContext context) {
    return ArDriveCard(
      height: 513,
      contentPadding: EdgeInsets.zero,
      content: Column(
        children: [
          Flexible(
            flex: 1,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 26, right: 26),
                child: ArDriveClickArea(
                  child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: ArDriveIcons.x()),
                ),
              ),
            ),
          ),
          Flexible(
            flex: 1,
            child: Column(
              children: [
                ArDriveIcons.checkCirle(
                  size: 40,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeSuccessDefault,
                ),
                Text(appLocalizationsOf(context).paymentSuccessful,
                    style: ArDriveTypography.body.leadBold()),
                const SizedBox(height: 16),
                Text(
                  appLocalizationsOf(context)
                      .yourCreditsWillBeAddedToYourAccount,
                  style: ArDriveTypography.body.buttonNormalRegular(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            flex: 1,
            child: Align(
              alignment: Alignment.center,
              child: ArDriveButton(
                maxHeight: 44,
                maxWidth: 143,
                text: appLocalizationsOf(context).close,
                fontStyle: ArDriveTypography.body.buttonLargeBold(
                  color: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
                Text('Payment Successful!',
                    style: ArDriveTypography.body.leadBold()),
                const SizedBox(height: 16),
                Text(
                  'Your credits will be added to your account soon. You can close this window.',
                  style: ArDriveTypography.body.buttonNormalRegular(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentDisabled,
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
                // TODO: localize
                text: 'Close',
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

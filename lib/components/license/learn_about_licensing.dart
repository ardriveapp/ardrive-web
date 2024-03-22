import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class LearnAboutLicensing extends StatelessWidget {
  const LearnAboutLicensing({super.key});

  @override
  Widget build(BuildContext context) {
    return ArDriveClickArea(
      child: GestureDetector(
        onTap: () {
          openUrl(
            url: Resources.licenseHelpLink,
          );
        },
        child: Text(
          'Learn More about Licensing',
          style: ArDriveTypography.body
              .buttonNormalRegular()
              .copyWith(decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}

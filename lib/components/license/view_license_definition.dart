import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

viewLicenseDefinitionTextSpan(
  BuildContext context,
  String licenseDefinitionTxId,
) =>
    TextSpan(
      text: 'View',
      style: ArDriveTypography.body
          .buttonLargeRegular(
            color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
          )
          .copyWith(
            decoration: TextDecoration.underline,
          ),
      recognizer: TapGestureRecognizer()
        ..onTap = () async {
          final url = 'https://ardrive.net/$licenseDefinitionTxId';
          await openUrl(url: url);
        },
    );

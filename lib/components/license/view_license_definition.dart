import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// "View": a link to the license's definition on the gateway, for placing
/// beside a license's name in text.
InlineSpan viewLicenseDefinitionTextSpan(
  BuildContext context,
  String licenseDefinitionTxId,
) =>
    ArDriveLink.span(
      text: 'View',
      style: ArDriveTypographyNew.of(context).paragraphLarge(),
      color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
      external: true,
      onTap: () => openUrl(
        url: 'https://turbo-gateway.com/$licenseDefinitionTxId',
      ),
    );

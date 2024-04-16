import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TruncatedAddressNew extends StatelessWidget {
  final String walletAddress;
  final int offsetStart;
  final int offsetEnd;

  const TruncatedAddressNew({
    super.key,
    required this.walletAddress,
    this.offsetStart = 6,
    this.offsetEnd = 5,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          openUrl(
            url: 'https://viewblock.io/arweave/address/$walletAddress',
          );
        },
        child: Text(
          truncateString(
            walletAddress,
            offsetStart: offsetStart,
            offsetEnd: offsetEnd,
          ),
          style: typography.paragraphNormal(
            color: colorTokens.textLink,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
      ),
    );
  }
}

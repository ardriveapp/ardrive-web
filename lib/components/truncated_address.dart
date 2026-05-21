import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TruncatedAddress extends StatelessWidget {
  final String walletAddress;
  final double? fontSize;
  final int offsetStart;
  final int offsetEnd;

  /// Custom explorer URL. If null, defaults to Arweave viewblock.
  final String? explorerUrl;

  const TruncatedAddress({
    super.key,
    required this.walletAddress,
    this.fontSize,
    this.offsetStart = 6,
    this.offsetEnd = 5,
    this.explorerUrl,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final url = explorerUrl ??
        'https://viewblock.io/arweave/address/$walletAddress';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          openUrl(url: url);
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

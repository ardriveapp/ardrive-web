import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TruncatedAddress extends StatelessWidget {
  final String walletAddress;
  final double? fontSize;
  final int offsetStart;
  final int offsetEnd;

  const TruncatedAddress({
    Key? key,
    required this.walletAddress,
    this.fontSize,
    this.offsetStart = 6,
    this.offsetEnd = 5,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
          style: ArDriveTypography.body.captionRegular().copyWith(
                fontWeight: FontWeight.w600,
                fontSize: fontSize,
                decoration: TextDecoration.underline,
              ),
        ),
      ),
    );
  }
}

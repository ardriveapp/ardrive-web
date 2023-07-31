import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TruncatedAddress extends StatelessWidget {
  final String walletAddress;
  final double? fontSize;

  const TruncatedAddress({Key? key, required this.walletAddress, this.fontSize})
      : super(key: key);

  String get _croppedAddress {
    final beginning = walletAddress.substring(0, 6);
    final end = walletAddress.substring(walletAddress.length - 5);
    return '$beginning...$end';
  }

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
          _croppedAddress,
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

import 'package:ardrive/entities/address_type.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TruncatedAddress extends StatelessWidget {
  final String walletAddress;
  final double? fontSize;
  final Color? color;
  final int offsetStart;
  final int offsetEnd;
  final AddressType addressType;

  const TruncatedAddress({
    Key? key,
    required this.walletAddress,
    this.fontSize,
    this.color,
    this.offsetStart = 6,
    this.offsetEnd = 5,
    this.addressType = AddressType.arweave,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    late final String url;
    switch (addressType) {
      case AddressType.arweave:
        url = 'https://viewblock.io/arweave/address/$walletAddress';
        break;
      case AddressType.ethereum:
        url = 'https://etherscan.io/address/$walletAddress';
        break;
    }

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
          style: ArDriveTypography.body.captionRegular(color: color).copyWith(
                fontWeight: FontWeight.w600,
                fontSize: fontSize,
                decoration: TextDecoration.underline,
              ),
        ),
      ),
    );
  }
}

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.walletAddress,
  });

  final String walletAddress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
          width: 2,
        ),
      ),
      width: 101,
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ArDriveIcons.person(),
          Text(
            '${walletAddress.substring(0, 2)}...${walletAddress.substring(walletAddress.length - 2)}',
            style: ArDriveTypography.body.buttonNormalBold(),
          ),
        ],
      ),
    );
  }
}

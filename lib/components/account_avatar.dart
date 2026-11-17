import 'package:ardrive/components/wallet_gradient_avatar.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The picture of an account: its ArNS logo, round, when it has one, and
/// the pixel avatar of its wallet address otherwise, or when the logo
/// can't be loaded. Always [size] square, so nothing moves around it.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.address,
    this.logo,
    this.size = 56,
  });

  final String address;

  /// An http(s) URL, or the id of the transaction holding the picture.
  final String? logo;
  final double size;

  /// Where [logo] is fetched from, or null when there is none.
  static String? logoUrl(String? logo) {
    if (logo == null || logo.isEmpty) return null;
    return logo.startsWith('http') ? logo : 'https://turbo-gateway.com/$logo';
  }

  @override
  Widget build(BuildContext context) {
    final url = logoUrl(logo);
    Widget gradient() => WalletGradientAvatar(address: address, size: size);
    return SizedBox(
      width: size,
      height: size,
      child: url == null
          ? gradient()
          : ClipOval(
              child: ArDriveImage(
                image: NetworkImage(url),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => gradient(),
              ),
            ),
    );
  }
}

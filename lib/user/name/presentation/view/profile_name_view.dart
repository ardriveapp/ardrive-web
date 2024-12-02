import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/truncated_address.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/user/download_wallet/download_wallet_modal.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProfileNameView extends StatelessWidget {
  const ProfileNameView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileNameBloc, ProfileNameState>(
      builder: (context, state) {
        final typography = ArDriveTypographyNew.of(context);
        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

        if (state is ProfileNameLoaded) {
          return Text(
            state.primaryName,
            style: typography.paragraphNormal(
              color: colorTokens.textLink,
              fontWeight: ArFontWeight.semiBold,
            ),
          );
        }

        return _buildWalletAddressRow(context, state.walletAddress);
      },
    );
  }

  Widget _buildWalletAddressRow(BuildContext context, String walletAddress) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              if (walletAddress.isNotEmpty)
                TruncatedAddress(
                  walletAddress: walletAddress,
                  fontSize: 18,
                ),
              const Spacer(),
              ArDriveIconButton(
                icon: ArDriveIcons.download(
                  color: colorTokens.textHigh,
                  size: 21,
                ),
                onPressed: () {
                  showDownloadWalletModal(context);
                },
              ),
              CopyButton(
                size: 21,
                text: walletAddress,
                showCopyText: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

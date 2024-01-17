import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../../misc/misc.dart';
import '../../components/login_card.dart';
import '../../components/max_device_sizes_constrained_box.dart';

class DownloadWalletView extends StatefulWidget {
  const DownloadWalletView(
      {super.key, required this.mnemonic, required this.wallet});

  final String mnemonic;
  final Wallet wallet;

  @override
  State<DownloadWalletView> createState() => _DownloadWalletViewState();
}

class _DownloadWalletViewState extends State<DownloadWalletView> {
  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.walletDownloadPage);
  }

  @override
  Widget build(BuildContext context) {
    return MaxDeviceSizesConstrainedBox(
      defaultMaxHeight: 798,
      maxHeightPercent: 1,
      child: LoginCard(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ScreenTypeLayout.builder(
                desktop: (context) => const SizedBox.shrink(),
                mobile: (context) => ArDriveImage(
                  image: AssetImage(Resources.images.brand.logo1),
                  height: 50,
                ),
              ),
              ArDriveIcons.checkmark(
                  size: 32,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeSuccessDefault),
              const SizedBox(height: 16),
              Text(
                // TODO: create/update localization key
                'Wallet Created',
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline
                    .headline4Regular(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault)
                    .copyWith(fontSize: 32),
              ),
              const SizedBox(height: 8),
              Text(
                // TODO: create/update localization key
                'Download your keyfile. You can also find it under the profile menu.',
                textAlign: TextAlign.center,
                style: ArDriveTypography.body.smallBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgSubtle),
              ),
              const SizedBox(height: 56),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                    onTap: () {
                      _onDownload();
                      PlausibleEventTracker.trackPageview(
                        page: PlausiblePageView.walletDownloaded,
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeBorderDefault,
                              width: 1),
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeBgSurface),
                      padding: const EdgeInsets.all(6),
                      child: Container(
                          width: double.maxFinite,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              // border: Border.all(color: ArDriveTheme.of(context).themeData.colors.themeBorderDefault, width: 1),
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeBgSubtle),
                          padding: const EdgeInsets.all(44),
                          child: Column(
                            children: [
                              ArDriveIcons.download2(size: 40),
                              const SizedBox(height: 4),
                              // TODO: create/update localization key
                              Text('Download Keyfile',
                                  style: ArDriveTypography.body.smallBold700(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgDefault))
                            ],
                          )),
                    )),
              ),
              const SizedBox(height: 56),
              SizedBox(
                width: double.infinity,
                child: ArDriveButton(
                  onPressed: () {
                    context
                        .read<LoginBloc>()
                        .add(CompleteWalletGeneration(widget.wallet));
                  },
                  // TODO: create/update localization key
                  text: 'Continue',
                  fontStyle:
                      ArDriveTypography.body.smallBold700(color: Colors.white),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _onDownload() async {
    final ioUtils = ArDriveIOUtils();

    await ioUtils.downloadWalletAsJsonFile(
      wallet: widget.wallet,
    );
  }
}

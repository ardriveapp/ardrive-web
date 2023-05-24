import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'top_up_dialog.dart';

class TurboBalance extends StatelessWidget {
  const TurboBalance({
    Key? key,
    required this.paymentService,
    required this.wallet,
  }) : super(key: key);

  final Wallet wallet;
  final PaymentService paymentService;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  Resources.images.brand.turbo,
                  height: 15,
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                  colorBlendMode: BlendMode.srcIn,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 4),
                FutureBuilder<BigInt>(
                    future: paymentService.getBalance(wallet: wallet),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        if (snapshot.hasError) {
                          return Text(
                            appLocalizationsOf(context).turboAddCreditsBlurb,
                            style: ArDriveTypography.body
                                .captionRegular()
                                .copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeFgMuted,
                                ),
                          );
                        }
                      }
                      if (snapshot.hasData) {
                        final balance = snapshot.data;
                        if (balance != null) {
                          return Text(
                            '${double.tryParse(winstonToAr(balance))?.toStringAsFixed(5) ?? 0} ${appLocalizationsOf(context).creditsTurbo}',
                            style: ArDriveTypography.body
                                .captionRegular()
                                .copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeFgSubtle,
                                ),
                          );
                        }
                      }
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      );
                    }),
              ],
            ),
          ),
          Flexible(
            flex: 2,
            child: SizedBox(
              height: 23,
              child: ArDriveButton(
                style: ArDriveButtonStyle.secondary,
                text: appLocalizationsOf(context).addButtonTurbo,
                fontStyle: TextStyle(
                  fontSize: 13,
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                  fontWeight: FontWeight.w700,
                ),
                borderRadius: 20,
                onPressed: () {
                  showAnimatedDialog(context, content: TopUpDialog());
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

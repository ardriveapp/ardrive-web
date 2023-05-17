import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/material.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'turbo',
                  style: ArDriveTypography.body.buttonNormalBold(),
                ),
                FutureBuilder<BigInt>(
                    future: paymentService.getBalance(wallet: wallet),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        if (snapshot.error is TurboUserNotFound) {
                          return Text(
                            'Add credits using your card for faster uploads',
                            style: ArDriveTypography.body.tinyRegular(),
                          );
                        } else {
                          return Text(
                            'Error fetching balance',
                            style: ArDriveTypography.body.tinyRegular(),
                          );
                        }
                      }
                      if (snapshot.hasData) {
                        final balance = snapshot.data;
                        if (balance != null) {
                          return Text(
                            '${winstonToAr(balance)} credits',
                            style: ArDriveTypography.body.tinyRegular(),
                          );
                        }
                      }
                      return Text(
                        'Fetching balance...',
                        style: ArDriveTypography.body.tinyRegular(),
                      );
                    }),
              ],
            ),
          ),
          Flexible(
            flex: 2,
            child: SizedBox(
              height: 23,
              width: 44,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ArDriveButton(
                  text: 'Add',
                  onPressed: () {},
                  style: ArDriveButtonStyle.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

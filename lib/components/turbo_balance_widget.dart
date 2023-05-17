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
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
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
                  style: ArDriveTypography.body.buttonLargeBold(),
                ),
                FutureBuilder<BigInt>(
                    future: paymentService.getBalance(wallet: wallet),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        if (snapshot.error is TurboUserNotFound) {
                          return Text(
                            'Add credits using your card for faster uploads',
                            style: ArDriveTypography.body.buttonNormalBold(),
                          );
                        } else {
                          return Text(
                            'Error fetching balance',
                            style: ArDriveTypography.body.buttonNormalBold(),
                          );
                        }
                      }
                      if (snapshot.hasData) {
                        final balance = snapshot.data;
                        if (balance != null) {
                          return Text(
                            '${double.tryParse(winstonToAr(balance))?.toStringAsFixed(5) ?? 0} credits',
                            style: ArDriveTypography.body.buttonNormalBold(),
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
              child: OutlinedButton(
                style: ButtonStyle(
                  shape: MaterialStateProperty.resolveWith<OutlinedBorder>(
                    (Set<MaterialState> states) {
                      return RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      );
                    },
                  ),
                  side: MaterialStateProperty.resolveWith<BorderSide?>(
                    (Set<MaterialState> states) {
                      return BorderSide(
                        width: 1,
                        style: BorderStyle.solid,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      );
                    },
                  ),
                  foregroundColor: MaterialStateProperty.resolveWith<Color?>(
                      (Set<MaterialState> states) {
                    return ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault;
                  }),
                ),
                onPressed: () {},
                child: const Text('Add'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

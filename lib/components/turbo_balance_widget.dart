import 'package:ardrive/blocs/turbo_balance/turbo_balance_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/winston_to_ar.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
                BlocBuilder<TurboBalanceCubit, TurboBalanceState>(
                    bloc: TurboBalanceCubit(
                      paymentService: paymentService,
                      wallet: wallet,
                    )..getBalance(),
                    builder: (context, state) {
                      if (state is NewTurboUserState) {
                        return Text(
                          appLocalizationsOf(context).turboAddCreditsBlurb,
                          style:
                              ArDriveTypography.body.captionRegular().copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgMuted,
                                  ),
                        );
                      } else if (state is TurboBalanceSuccessState) {
                        final balance = state.balance;

                        return Text(
                          '${winstonToAr(balance).toStringAsFixed(5)} ${appLocalizationsOf(context).creditsTurbo}',
                          style:
                              ArDriveTypography.body.captionRegular().copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 18,
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgSubtle,
                                  ),
                        );
                      } else if (state is TurboBalanceLoading) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(),
                        );
                      } else if (state is TurboBalanceErrorState) {
                        return Text(
                          appLocalizationsOf(context).error,
                          style:
                              ArDriveTypography.body.captionRegular().copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeErrorDefault,
                                  ),
                        );
                      }
                      return const SizedBox();
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
                onPressed: () {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:ardrive/components/turbo_logo.dart';
import 'package:ardrive/cookie_policy_consent/views/cookie_policy_consent_modal.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_balance/turbo_balance_cubit.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TurboBalance extends StatefulWidget {
  const TurboBalance({
    Key? key,
    required this.paymentService,
    required this.wallet,
    this.onTapAddButton,
  }) : super(key: key);

  final Wallet wallet;
  final PaymentService paymentService;
  final Function? onTapAddButton;

  @override
  State<TurboBalance> createState() => _TurboBalanceState();
}

class _TurboBalanceState extends State<TurboBalance> {
  late TurboBalanceCubit _turboBalanceCubit;

  @override
  void initState() {
    super.initState();
    _turboBalanceCubit = TurboBalanceCubit(
      paymentService: widget.paymentService,
      wallet: widget.wallet,
    )..getBalance();
  }

  Widget addButton(BuildContext context) {
    const isHidden = !kIsWeb;

    return SizedBox(
      height: 23,
      child: isHidden
          ? null
          : ArDriveButton(
              style: ArDriveButtonStyle.secondary,
              text: appLocalizationsOf(context).addButtonTurbo,
              fontStyle: TextStyle(
                fontSize: 13,
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                fontWeight: FontWeight.w700,
              ),
              borderRadius: 20,
              onPressed: () {
                showCookiePolicyConsentModal(context, (context) {
                  showTurboTopupModal(context);
                });

                widget.onTapAddButton?.call();
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          turboLogo(context, height: 15),
          const SizedBox(height: 8),
          BlocBuilder<TurboBalanceCubit, TurboBalanceState>(
            bloc: _turboBalanceCubit,
            builder: (context, state) {
              if (state is NewTurboUserState) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      flex: 2,
                      child: Text(
                        appLocalizationsOf(context).turboAddCreditsBlurb,
                        style: ArDriveTypography.body
                            .captionRegular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgSubtle)
                            .copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    Flexible(
                      flex: 1,
                      child: addButton(context),
                    )
                  ],
                );
              } else if (state is TurboBalanceSuccessState) {
                final balance = state.balance;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '${convertCreditsToLiteralString(balance)} ${appLocalizationsOf(context).credits}',
                      style: ArDriveTypography.body.captionRegular().copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgMuted,
                          ),
                    ),
                    addButton(context),
                  ],
                );
              } else if (state is TurboBalanceLoading) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                );
              } else if (state is TurboBalanceErrorState) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      appLocalizationsOf(context).error,
                      style: ArDriveTypography.body.captionRegular().copyWith(
                            fontWeight: FontWeight.w600,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeErrorDefault,
                          ),
                    ),
                    ArDriveIconButton(
                      icon: ArDriveIcons.refresh(),
                      onPressed: () {
                        logger.d('Refreshing balance');
                        _turboBalanceCubit.getBalance();
                      },
                    )
                  ],
                );
              }
              return const SizedBox();
            },
          ),
        ],
      ),
    );
  }
}

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/gift/bloc/redeem_gift_bloc.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/topup/views/topup_review_view.dart';
import 'package:ardrive/turbo/topup/views/topup_success_view.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

class RedeemGiftModal extends StatefulWidget {
  const RedeemGiftModal({super.key});

  @override
  State<RedeemGiftModal> createState() => _RedeemGiftModalState();
}

class _RedeemGiftModalState extends State<RedeemGiftModal>
    with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _giftCodeController = TextEditingController();
  final ConfettiController _confettiController = ConfettiController(
    duration: const Duration(seconds: 5),
  );

  late final AnimationController _opacityController;

  bool _isEmailValid = false;
  bool _isGiftCodeValid = false;

  @override
  initState() {
    super.initState();
    _opacityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300)).then((_) {
        if (mounted) _opacityController.forward();
      });
    });
  }

  @override
  dispose() {
    _opacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

    // custom theme for the text fields on the top-up form
    final textTheme = theme.copyWith(
      textFieldTheme: theme.textFieldTheme.copyWith(
        inputBackgroundColor: theme.colors.themeBgCanvas,
        labelColor: theme.colors.themeFgDefault,
        requiredLabelColor: theme.colors.themeFgDefault,
        inputTextStyle: theme.textFieldTheme.inputTextStyle.copyWith(
          color: theme.colors.themeFgMuted,
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 8,
        ),
        labelStyle: TextStyle(
          color: theme.colors.themeFgDefault,
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: ArDriveStandardModal(
        hasCloseButton: true,
        width: kLargeDialogWidth + 200,
        title: appLocalizationsOf(context).redeemYourGift,
        actions: [
          ModalAction(
            action: () {
              Navigator.of(context).pop();
            },
            title: appLocalizationsOf(context).cancel,
          ),
          ModalAction(
            isEnable: _isEmailValid && _isGiftCodeValid,
            action: () {
              context.read<RedeemGiftBloc>().add(RedeemGiftLoad(
                  giftCode: _giftCodeController.text,
                  email: _emailController.text));
            },
            title: appLocalizationsOf(context).confirm,
          )
        ],
        content: BlocConsumer<RedeemGiftBloc, RedeemGiftState>(
            listener: (context, state) {
          if (state is RedeemGiftLoading) {
            _opacityController.reset();

            WidgetsBinding.instance.addPostFrameCallback((_) {
              Future.delayed(const Duration(milliseconds: 300)).then((_) {
                if (mounted) _opacityController.forward();
              });
            });
          }
          if (state is RedeemGiftSuccess) {
            _confettiController.play();
            context.read<ProfileCubit>().refreshBalance();
            Navigator.of(context).pop();

            showArDriveDialog(
              context,
              content: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: ArDriveStandardModal(
                  width: 575,
                  content: SuccessView(
                    showConfetti: true,
                    successMessage: appLocalizationsOf(context).giftRedeemed,
                    detailMessage: appLocalizationsOf(context)
                        .redemptionSuccessDescription,
                    closeButtonLabel: appLocalizationsOf(context).close,
                  ),
                ),
              ),
              barrierDismissible: false,
              barrierColor: ArDriveTheme.of(context)
                  .themeData
                  .colors
                  .shadow
                  .withOpacity(0.9),
            );
          } else if (state is RedeemGiftFailure) {
            showArDriveDialog(
              context,
              content: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: ArDriveStandardModal(
                  width: 575,
                  content: ErrorView(
                    errorTitle: appLocalizationsOf(context).invalidCode,
                    errorMessage:
                        appLocalizationsOf(context).redemptionErrorDescription,
                    onDismiss: () {
                      Navigator.of(context).pop();
                    },
                    onTryAgain: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
              barrierDismissible: false,
              barrierColor: ArDriveTheme.of(context)
                  .themeData
                  .colors
                  .shadow
                  .withOpacity(0.9),
            );
          } else if (state is RedeemGiftAlreadyRedeemed) {
            showArDriveDialog(
              context,
              content: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: ArDriveStandardModal(
                  width: 575,
                  content: ErrorView(
                    errorTitle: appLocalizationsOf(context).codeAlreadyUsed,
                    errorMessage:
                        appLocalizationsOf(context).codeAlreadyUsedDescription,
                    onDismiss: () {
                      Navigator.of(context).pop();
                    },
                    onTryAgain: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
              barrierDismissible: false,
              barrierColor: ArDriveTheme.of(context)
                  .themeData
                  .colors
                  .shadow
                  .withOpacity(0.9),
            );
          }
        }, builder: (context, state) {
          Widget child;
          if (state is RedeemGiftLoading) {
            child = const SizedBox(
                height: 350, child: Center(child: CircularProgressIndicator()));
          } else {
            child = Column(
              children: [
                Text(
                  appLocalizationsOf(context)
                      .confirmTheEmailAddressTheGiftWasSentTo,
                  style: ArDriveTypography.body
                      .buttonNormalBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeAccentDisabled,
                      )
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(
                  height: 64,
                ),
                ArDriveTheme(
                  themeData: textTheme,
                  child: ScreenTypeLayout.builder(
                    mobile: (context) {
                      return Column(
                        children: [
                          SizedBox(height: 100, child: _emailField()),
                          const SizedBox(
                            height: 16,
                          ),
                          SizedBox(height: 100, child: _giftCodeField()),
                        ],
                      );
                    },
                    desktop: (context) {
                      return SizedBox(
                        height: 100,
                        child: Row(
                          children: [
                            Flexible(
                              flex: 1,
                              child: _emailField(),
                            ),
                            const SizedBox(
                              width: 16,
                            ),
                            Flexible(
                              flex: 1,
                              child: _giftCodeField(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(
                  height: 64,
                ),
                Divider(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeBorderDefault,
                ),
              ],
            );
          }
          return AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: FadeTransition(
              opacity: _opacityController,
              child: child,
            ),
          );
        }),
      ),
    );
  }

  Widget _emailField() {
    return ArDriveTextField(
      label: appLocalizationsOf(context).email,
      validator: (s) {
        if (s == null || s.isEmpty || isEmailValid(s)) {
          setState(() {
            _isEmailValid = true;
          });
          return null;
        }

        setState(() {
          _isEmailValid = false;
        });

        return appLocalizationsOf(context).pleaseEnterAValidEmail;
      },
      onFieldSubmitted: (s) {
        if (_isEmailValid && _isGiftCodeValid) {
          context.read<RedeemGiftBloc>().add(RedeemGiftLoad(
              giftCode: _giftCodeController.text,
              email: _emailController.text));
        }
      },
      controller: _emailController,
      onChanged: (s) {},
    );
  }

  Widget _giftCodeField() {
    return ArDriveTextField(
      controller: _giftCodeController,
      onFieldSubmitted: (s) {
        if (_isEmailValid && _isGiftCodeValid) {
          context.read<RedeemGiftBloc>().add(RedeemGiftLoad(
              giftCode: _giftCodeController.text,
              email: _emailController.text));
        }
      },
      validator: (s) {
        if (s == null || !isValidUuidV4(s)) {
          setState(() {
            _isGiftCodeValid = false;
          });
          return appLocalizationsOf(context).theGiftCodeProvidedIsInvalid;
        }

        setState(() {
          _isGiftCodeValid = true;
        });

        return null;
      },
      label: appLocalizationsOf(context).giftCode,
    );
  }
}

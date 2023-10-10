import 'package:ardrive/components/turbo_logo.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/turbo/topup/blocs/payment_review/payment_review_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/views/topup_payment_form.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

class TurboReviewView extends StatefulWidget {
  final bool dryRun;
  const TurboReviewView({
    super.key,
    required this.dryRun,
  });

  @override
  State<TurboReviewView> createState() => _TurboReviewViewState();
}

class _TurboReviewViewState extends State<TurboReviewView> {
  final _emailController = TextEditingController();
  bool _emailChecked = false;
  bool _emailIsValid = true;
  bool _hasAutomaticChecked = false;
  bool _isTermsChecked = false;

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

    return BlocListener<PaymentReviewBloc, PaymentReviewState>(
      listener: (context, state) {
        if (state is PaymentReviewPaymentSuccess) {
          context
              .read<TurboTopupFlowBloc>()
              .add(const TurboTopUpShowSuccessView());
        } else if (state is PaymentReviewPaymentError) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModal(
              width: 575,
              content: TurboErrorView(
                errorType: state.errorType,
                onDismiss: () {
                  context
                      .read<TurboTopupFlowBloc>()
                      .add(const TurboTopUpShowPaymentFormView(4));
                },
                onTryAgain: () {
                  Navigator.pop(context);
                  context
                      .read<TurboTopupFlowBloc>()
                      .add(const TurboTopUpShowPaymentFormView(4));
                },
              ),
            ),
            barrierDismissible: false,
            barrierColor: ArDriveTheme.of(context)
                .themeData
                .colors
                .shadow
                .withOpacity(0.9),
          );
        } else if (state is PaymentReviewErrorLoadingPaymentModel) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModal(
              width: 575,
              content: TurboErrorView(
                errorType: TurboErrorType.fetchPaymentIntentFailed,
                onDismiss: () {
                  context
                      .read<TurboTopupFlowBloc>()
                      .add(const TurboTopUpShowPaymentFormView(4));
                },
                onTryAgain: () {
                  Navigator.pop(context);
                  context.read<PaymentReviewBloc>().add(
                        PaymentReviewLoadPaymentModel(),
                      );
                },
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
      },
      child: BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
        buildWhen: (previous, current) {
          return current is PaymentReviewPaymentModelLoaded ||
              current is PaymentReviewLoadingPaymentModel;
        },
        builder: (context, state) {
          if (state is PaymentReviewLoadingPaymentModel) {
            return const TurboTopupScaffold(
              child: SizedBox(
                height: 575,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 26, right: 26),
                    child: ArDriveClickArea(
                      child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: ArDriveIcons.x()),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 40.0),
                    child: Text(
                      appLocalizationsOf(context).review,
                      style: ArDriveTypography.body
                          .leadBold()
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: ArDriveCard(
                    contentPadding: const EdgeInsets.all(0),
                    backgroundColor:
                        ArDriveTheme.of(context).themeData.colors.shadow,
                    content: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 24, left: 24, right: 24),
                          child: BlocBuilder<PaymentReviewBloc,
                              PaymentReviewState>(
                            builder: (context, paymentReviewBlocState) =>
                                Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: turboLogo(context, height: 15),
                                ),
                                const SizedBox(
                                  height: 18,
                                ),
                                BlocBuilder<PaymentReviewBloc,
                                    PaymentReviewState>(
                                  buildWhen: (previous, current) {
                                    return current
                                        is PaymentReviewPaymentModelLoaded;
                                  },
                                  builder: (context, state) {
                                    if (state
                                        is PaymentReviewPaymentModelLoaded) {
                                      return Text(
                                        state.credits,
                                        style: ArDriveTypography.headline
                                            .headline4Regular(
                                              color: ArDriveTheme.of(context)
                                                  .themeData
                                                  .colors
                                                  .themeFgMuted,
                                            )
                                            .copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      );
                                    }

                                    return Text(
                                      '0',
                                      style: ArDriveTypography.headline
                                          .headline4Regular(
                                        color: ArDriveTheme.of(context)
                                            .themeData
                                            .colors
                                            .themeFgMuted,
                                      ),
                                    );
                                  },
                                ),
                                Text(
                                  appLocalizationsOf(context).credits,
                                  style:
                                      ArDriveTypography.body.buttonLargeRegular(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgDefault,
                                  ),
                                ),
                                const SizedBox(
                                  height: 40,
                                ),
                                const Divider(),
                                if (paymentReviewBlocState
                                        is PaymentReviewPaymentModelLoaded &&
                                    paymentReviewBlocState.promoDiscount !=
                                        null) ...[
                                  Row(
                                    children: [
                                      Text(
                                        'Subtotal',
                                        style: ArDriveTypography.body
                                            .buttonNormalRegular()
                                            .copyWith(
                                              color: ArDriveTheme.of(context)
                                                  .themeData
                                                  .colors
                                                  .themeFgDisabled,
                                            ),
                                      ),
                                      const Spacer(),
                                      BlocBuilder<PaymentReviewBloc,
                                          PaymentReviewState>(
                                        buildWhen: (previous, current) {
                                          return current
                                              is PaymentReviewPaymentModelLoaded;
                                        },
                                        builder: (context, state) {
                                          if (state
                                              is PaymentReviewPaymentModelLoaded) {
                                            return Text(
                                              '\$${state.subTotal}',
                                              style: ArDriveTypography.body
                                                  .buttonNormalRegular()
                                                  .copyWith(
                                                    color:
                                                        ArDriveTheme.of(context)
                                                            .themeData
                                                            .colors
                                                            .themeFgDisabled,
                                                  ),
                                            );
                                          }

                                          return Text(
                                            '\$0',
                                            style: ArDriveTypography.body
                                                .buttonNormalRegular()
                                                .copyWith(
                                                  color:
                                                      ArDriveTheme.of(context)
                                                          .themeData
                                                          .colors
                                                          .themeFgDisabled,
                                                ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  Row(
                                    children: [
                                      Text(
                                        'Discount',
                                        style: ArDriveTypography.body
                                            .buttonNormalRegular()
                                            .copyWith(
                                              color: ArDriveTheme.of(context)
                                                  .themeData
                                                  .colors
                                                  .themeFgDisabled,
                                            ),
                                      ),
                                      const Spacer(),
                                      BlocBuilder<PaymentReviewBloc,
                                          PaymentReviewState>(
                                        buildWhen: (previous, current) {
                                          return current
                                                  is PaymentReviewPaymentModelLoaded &&
                                              current.promoDiscount != null;
                                        },
                                        builder: (context, state) {
                                          if (state
                                              is PaymentReviewPaymentModelLoaded) {
                                            return Text(
                                              state.promoDiscount!,
                                              style: ArDriveTypography.body
                                                  .buttonNormalRegular()
                                                  .copyWith(
                                                    color:
                                                        ArDriveTheme.of(context)
                                                            .themeData
                                                            .colors
                                                            .themeFgDisabled,
                                                  ),
                                            );
                                          }

                                          return Container();
                                        },
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                ],
                                Row(
                                  children: [
                                    Text(
                                      appLocalizationsOf(context).total,
                                      style: ArDriveTypography.body
                                          .buttonNormalBold(),
                                    ),
                                    const Spacer(),
                                    BlocBuilder<PaymentReviewBloc,
                                        PaymentReviewState>(
                                      buildWhen: (previous, current) {
                                        return current
                                            is PaymentReviewPaymentModelLoaded;
                                      },
                                      builder: (context, state) {
                                        if (state
                                            is PaymentReviewPaymentModelLoaded) {
                                          return Text(
                                            '\$${state.total}',
                                            style: ArDriveTypography.body
                                                .buttonNormalBold()
                                                .copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          );
                                        }

                                        return Text(
                                          '\$0',
                                          style: ArDriveTypography.body
                                              .buttonNormalBold()
                                              .copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 24,
                        ),
                        BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
                          builder: (context, state) {
                            if (state is PaymentReviewPaymentModelLoaded) {
                              return Container(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeBgSurface,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 24,
                                ),
                                child: Row(
                                  children: [
                                    TimerWidget(
                                      humanReadable: false,
                                      key: state is PaymentReviewQuoteLoaded
                                          ? const ValueKey('quote_loaded')
                                          : null,
                                      durationInSeconds: state
                                          .quoteExpirationDate
                                          .difference(DateTime.now())
                                          .inSeconds,
                                      onFinished: () {
                                        context
                                            .read<PaymentReviewBloc>()
                                            .add(PaymentReviewRefreshQuote());
                                      },
                                      isFetching:
                                          state is PaymentReviewLoadingQuote,
                                      hasError: state is PaymentReviewEvent,
                                    ),
                                    const Spacer(),
                                    const RefreshQuoteButton(),
                                  ],
                                ),
                              );
                            }
                            return Container();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.only(left: 40.0, right: 40, bottom: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appLocalizationsOf(context)
                            .leaveAnEmailToReceiveAReceipt,
                        style: ArDriveTypography.body.buttonNormalBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      ArDriveTheme(
                        key: const ValueKey('turbo_payment_form'),
                        themeData: textTheme,
                        child: ArDriveTextField(
                          validator: (s) {
                            if (s == null || s.isEmpty || isEmailValid(s)) {
                              setState(() {
                                _emailIsValid = true;
                              });
                              return null;
                            }
                            setState(() {
                              _emailIsValid = false;
                              _emailChecked = false;
                            });
                            return appLocalizationsOf(context)
                                .pleaseEnterAValidEmail;
                          },
                          controller: _emailController,
                          onChanged: (s) {
                            if (_hasAutomaticChecked) {
                              return;
                            }

                            if (_emailIsValid) {
                              setState(() {
                                _emailChecked = true;
                                _hasAutomaticChecked = true;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      ArDriveCheckBox(
                        isDisabled:
                            !_emailIsValid || _emailController.text.isEmpty,
                        key: ValueKey(
                            '${_emailIsValid && _emailChecked}${_emailController.text}'),
                        title: appLocalizationsOf(context)
                            .keepMeUpToDateOnNewsAndPromotions,
                        titleStyle: ArDriveTypography.body.buttonNormalBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
                        ),
                        onChange: (value) => setState(() {
                          _emailChecked = value;
                        }),
                        checked: _emailIsValid &&
                            _emailChecked &&
                            _emailController.text.isNotEmpty,
                      ),
                      ArDriveCheckBox(
                        titleWidget: Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: splitTranslationsWithMultipleStyles<
                                  InlineSpan>(
                                originalText: appLocalizationsOf(context)
                                    .aggreeToTerms_body,
                                defaultMapper: (text) => TextSpan(
                                  text: text,
                                  style:
                                      ArDriveTypography.body.buttonNormalBold(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgDefault,
                                  ),
                                ),
                                parts: {
                                  appLocalizationsOf(context).aggreeToTerms_link:
                                      (text) => TextSpan(
                                            text: text,
                                            style: ArDriveTypography.body
                                                .buttonNormalBold(
                                                  color:
                                                      ArDriveTheme.of(context)
                                                          .themeData
                                                          .colors
                                                          .themeFgDefault,
                                                )
                                                .copyWith(
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () => openUrl(
                                                    url:
                                                        Resources.agreementLink,
                                                  ),
                                          ),
                                },
                              ),
                            ),
                          ),
                        ),
                        checked: _isTermsChecked,
                        onChange: ((value) {
                          setState(() => _isTermsChecked = value);
                        }),
                      ),
                      const Divider(
                        height: 80,
                      ),
                      _footer(context)
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (context) => SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
              builder: (context, state) {
                return ScreenTypeLayout.builder(
                  // FIXME: the desktop section is never gonna be rendered
                  /// because its wrapped in another layout builder for mobile.
                  desktop: (context) => ArDriveButton(
                    maxHeight: 44,
                    maxWidth: 143,
                    text: appLocalizationsOf(context).pay,
                    fontStyle: ArDriveTypography.body.buttonLargeBold(
                      color: Colors.white,
                    ),
                    isDisabled: state is PaymentReviewLoadingQuote ||
                        !_emailIsValid ||
                        !_isTermsChecked,
                    customContent: state is PaymentReviewLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : null,
                    onPressed: () async {
                      if (state is PaymentReviewLoading) {
                        return;
                      }

                      context.read<PaymentReviewBloc>().add(
                            PaymentReviewFinishPayment(
                              email: _emailController.text,
                              userAcceptedToReceiveEmails: _emailChecked,
                              dryRun: widget.dryRun,
                            ),
                          );
                    },
                  ),
                  mobile: (context) => ArDriveButton(
                    maxHeight: 44,
                    maxWidth: double.maxFinite,
                    text: appLocalizationsOf(context).pay,
                    fontStyle: ArDriveTypography.body.buttonLargeBold(
                      color: Colors.white,
                    ),
                    isDisabled: state is PaymentReviewLoadingQuote ||
                        !_emailIsValid ||
                        !_isTermsChecked,
                    customContent: state is PaymentReviewLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : null,
                    onPressed: () async {
                      if (state is PaymentReviewLoading) {
                        return;
                      }

                      context.read<PaymentReviewBloc>().add(
                            PaymentReviewFinishPayment(
                              email: _emailController.text,
                              userAcceptedToReceiveEmails: _emailChecked,
                              dryRun: widget.dryRun,
                            ),
                          );
                    },
                  ),
                );
              },
            ),
            const SizedBox(
              height: 16,
            ),
            ArDriveClickArea(
              child: GestureDetector(
                onTap: () {
                  context.read<TurboTopupFlowBloc>().add(
                        const TurboTopUpShowPaymentFormView(4),
                      );
                },
                child: Text(
                  appLocalizationsOf(context).back,
                  style: ArDriveTypography.body.buttonLargeBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      desktop: (context) => SizedBox(
        width: double.maxFinite,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ArDriveClickArea(
              child: GestureDetector(
                onTap: () {
                  context.read<TurboTopupFlowBloc>().add(
                        const TurboTopUpShowPaymentFormView(4),
                      );
                },
                child: Text(
                  appLocalizationsOf(context).back,
                  style: ArDriveTypography.body.buttonLargeBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentDisabled,
                  ),
                ),
              ),
            ),
            BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
              builder: (context, state) {
                return ScreenTypeLayout.builder(
                  desktop: (context) => ArDriveButton(
                    maxHeight: 44,
                    maxWidth: 143,
                    text: appLocalizationsOf(context).pay,
                    fontStyle: ArDriveTypography.body.buttonLargeBold(
                      color: Colors.white,
                    ),
                    isDisabled: state is PaymentReviewLoadingQuote ||
                        !_emailIsValid ||
                        !_isTermsChecked,
                    customContent: state is PaymentReviewLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : null,
                    onPressed: () async {
                      if (state is PaymentReviewLoading) {
                        return;
                      }

                      context.read<PaymentReviewBloc>().add(
                            PaymentReviewFinishPayment(
                              email: _emailController.text,
                              userAcceptedToReceiveEmails: _emailChecked,
                              dryRun: widget.dryRun,
                            ),
                          );
                    },
                  ),
                  mobile: (context) => ArDriveButton(
                    maxHeight: 44,
                    maxWidth: double.maxFinite,
                    text: appLocalizationsOf(context).pay,
                    fontStyle: ArDriveTypography.body.buttonLargeBold(
                      color: Colors.white,
                    ),
                    isDisabled: state is PaymentReviewLoadingQuote ||
                        !_emailIsValid ||
                        !_isTermsChecked,
                    customContent: state is PaymentReviewLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : null,
                    onPressed: () async {
                      if (state is PaymentReviewLoading) {
                        return;
                      }

                      context.read<PaymentReviewBloc>().add(
                            PaymentReviewFinishPayment(
                              email: _emailController.text,
                              userAcceptedToReceiveEmails: _emailChecked,
                              dryRun: widget.dryRun,
                            ),
                          );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class RefreshButton extends StatefulWidget {
  final void Function() onPressed;

  const RefreshButton({super.key, required this.onPressed});

  @override
  RefreshButtonState createState() => RefreshButtonState();
}

class RefreshButtonState extends State<RefreshButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _animation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SlideTransition(
          position: _animation,
          child: ArDriveIconButton(
            onPressed: () {
              widget.onPressed();
              _controller.forward();
            },
            size: 14,
            icon: ArDriveIcons.refresh(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
        ),
        FadeTransition(
          opacity: _controller,
          child: Text(
            'Refresh',
            style: ArDriveTypography.body.buttonNormalBold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
        ),
      ],
    );
  }
}

class RefreshQuoteButton extends StatefulWidget {
  const RefreshQuoteButton({super.key});

  @override
  RefreshQuoteButtonState createState() => RefreshQuoteButtonState();
}

class RefreshQuoteButtonState extends State<RefreshQuoteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAndSizeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAndSizeAnimation =
        Tween<double>(begin: 1, end: 0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
      builder: (context, state) {
        if (state is PaymentReviewLoadingQuote) {
          _controller.forward();
        } else {
          _controller.reverse();
        }

        return ArDriveClickArea(
          child: GestureDetector(
            onTap: () {
              context
                  .read<PaymentReviewBloc>()
                  .add(PaymentReviewRefreshQuote());
            },
            child: Row(
              children: [
                if (state is PaymentReviewLoadingQuote)
                  const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                if (state is! PaymentReviewLoadingQuote)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: ArDriveIcons.refresh(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                      size: 16,
                    ),
                  ),
                const SizedBox(width: 4),
                FadeTransition(
                  opacity: _fadeAndSizeAnimation,
                  child: SizeTransition(
                    sizeFactor: _fadeAndSizeAnimation,
                    axis: Axis.horizontal,
                    axisAlignment: -1,
                    child: Text(
                      appLocalizationsOf(context).refresh,
                      style: ArDriveTypography.body.buttonNormalBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

bool isEmailValid(String email) {
  if (email.isEmpty) {
    return false;
  }

  // Check if email contains '@' and '.'
  if (!email.contains('@') || !email.contains('.')) {
    return false;
  }

  // Check the position of '@' and '.'
  var atSignIndex = email.indexOf('@');
  var dotIndex = email.lastIndexOf('.');

  if (dotIndex <= atSignIndex) {
    return false;
  }

  // Check if '@' and '.' are not the first or last characters
  if (atSignIndex == 0 ||
      dotIndex == 0 ||
      atSignIndex == email.length - 1 ||
      dotIndex == email.length - 1) {
    return false;
  }

  // Check if there is a domain after '.'
  var domain = email.substring(dotIndex + 1);
  if (domain.isEmpty) {
    return false;
  }

  // If none of the checks failed, the email is valid
  return true;
}

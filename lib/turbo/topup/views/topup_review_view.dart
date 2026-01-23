import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/turbo/topup/blocs/payment_review/payment_review_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/components/purchase_summary.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

class TurboReviewView extends StatefulWidget {
  const TurboReviewView({super.key});

  @override
  State<TurboReviewView> createState() => _TurboReviewViewState();
}

class _TurboReviewViewState extends State<TurboReviewView> {
  final _emailController = TextEditingController();
  bool _emailChecked = false;
  bool _emailIsValid = true;
  bool _hasAutomaticChecked = false;

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
          context.read<TurboTopupFlowBloc>().add(TurboTopUpShowSuccessView(
                amountPaid: '\$${state.total}',
                creditsReceived: state.credits,
                storageEstimate: state.storageEstimate,
                newBalanceStorage: state.newBalanceStorage,
              ));
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
                      .add(const TurboTopUpShowPaymentFormView(2));
                },
                onTryAgain: () {
                  Navigator.pop(context);
                  context
                      .read<TurboTopupFlowBloc>()
                      .add(const TurboTopUpShowPaymentFormView(2));
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
                      .add(const TurboTopUpShowPaymentFormView(2));
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

          return Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Red top line (ArDrive modal pattern)
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: theme.colorTokens.containerRed,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                    ),
                    // Main content
                    Container(
                      color: theme.colors.themeBgCanvas,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 32), // Space for close button
                          // Header
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              appLocalizationsOf(context).review,
                              style: ArDriveTypographyNew.of(context).heading5(
                                fontWeight: ArFontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Quote timer bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: BlocBuilder<PaymentReviewBloc,
                                PaymentReviewState>(
                              builder: (context, state) {
                                if (state is PaymentReviewPaymentModelLoaded) {
                                  return _QuoteTimerBar(
                                    expirationDate: state.quoteExpirationDate,
                                    isLoading:
                                        state is PaymentReviewLoadingQuote,
                                    onRefresh: () {
                                      context
                                          .read<PaymentReviewBloc>()
                                          .add(PaymentReviewRefreshQuote());
                                    },
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Checkout summary with balance info
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20.0),
                            child: BlocBuilder<PaymentReviewBloc,
                                PaymentReviewState>(
                              buildWhen: (previous, current) {
                                return current
                                    is PaymentReviewPaymentModelLoaded;
                              },
                              builder: (context, state) {
                                if (state is PaymentReviewPaymentModelLoaded) {
                                  // Parse discount percentage from promoDiscount string
                                  int? discountPercent;
                                  double? subtotal;
                                  if (state.promoDiscount != null &&
                                      state.subTotal != null) {
                                    subtotal = double.tryParse(state.subTotal!);
                                    // Calculate discount percentage from subtotal and total
                                    final total =
                                        double.tryParse(state.total) ?? 0;
                                    if (subtotal != null &&
                                        subtotal > 0 &&
                                        total < subtotal) {
                                      discountPercent =
                                          ((1 - (total / subtotal)) * 100)
                                              .round();
                                    }
                                  }

                                  return CheckoutSummary(
                                    creditsToReceive: state.creditsWinc,
                                    storageEstimate: state.storageEstimate,
                                    priceAmount:
                                        double.tryParse(state.total) ?? 0,
                                    priceSymbol: '\$',
                                    isPriceInToken: false,
                                    subtotal: subtotal,
                                    discountPercent: discountPercent,
                                    currentBalance: state.currentBalance,
                                    currentBalanceStorage:
                                        state.currentBalanceStorage,
                                    newBalanceStorage: state.newBalanceStorage,
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appLocalizationsOf(context)
                                      .leaveAnEmailToReceiveAReceipt,
                                  style: ArDriveTypographyNew.of(context)
                                      .paragraphSmall(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgDefault,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ArDriveTheme(
                                  key: const ValueKey('turbo_payment_form'),
                                  themeData: textTheme,
                                  child: ArDriveTextField(
                                    validator: (s) {
                                      if (s == null ||
                                          s.isEmpty ||
                                          isEmailValid(s)) {
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
                                const SizedBox(height: 12),
                                ArDriveCheckBox(
                                  isDisabled: !_emailIsValid ||
                                      _emailController.text.isEmpty,
                                  key: ValueKey(
                                      '${_emailIsValid && _emailChecked}${_emailController.text}'),
                                  title: appLocalizationsOf(context)
                                      .keepMeUpToDateOnNewsAndPromotions,
                                  titleStyle: ArDriveTypographyNew.of(context)
                                      .paragraphSmall(
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
                                const SizedBox(height: 16),
                                // Terms text (not a checkbox)
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text:
                                            'By continuing, you agree to the ',
                                        style: ArDriveTypographyNew.of(context)
                                            .paragraphSmall(
                                          color: ArDriveTheme.of(context)
                                              .themeData
                                              .colors
                                              .themeFgMuted,
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            'Terms of Service and Privacy Policy',
                                        style: ArDriveTypographyNew.of(context)
                                            .paragraphSmall(
                                              color: ArDriveTheme.of(context)
                                                  .themeData
                                                  .colors
                                                  .themeFgMuted,
                                            )
                                            .copyWith(
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () => openUrl(
                                                url: Resources.agreementLink,
                                              ),
                                      ),
                                      TextSpan(
                                        text: '.',
                                        style: ArDriveTypographyNew.of(context)
                                            .paragraphSmall(
                                          color: ArDriveTheme.of(context)
                                              .themeData
                                              .colors
                                              .themeFgMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _footer(context)
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Close button in top right
              Positioned(
                right: 27,
                top: 27,
                child: ArDriveClickArea(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: ArDriveIcons.x(),
                  ),
                ),
              ),
            ],
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
                return ArDriveButton(
                  maxHeight: 44,
                  maxWidth: double.maxFinite,
                  text: appLocalizationsOf(context).pay,
                  fontStyle: ArDriveTypographyNew.of(context).paragraphLarge(
                    fontWeight: ArFontWeight.bold,
                    color: Colors.white,
                  ),
                  isDisabled:
                      state is PaymentReviewLoadingQuote || !_emailIsValid,
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
                          ),
                        );
                  },
                );
              },
            ),
            const SizedBox(
              height: 24,
            ),
            ArDriveClickArea(
              child: GestureDetector(
                onTap: () {
                  context.read<TurboTopupFlowBloc>().add(
                        const TurboTopUpShowPaymentFormView(2),
                      );
                },
                child: Text(
                  appLocalizationsOf(context).back,
                  style: ArDriveTypographyNew.of(context).paragraphLarge(
                    fontWeight: ArFontWeight.bold,
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
                        const TurboTopUpShowPaymentFormView(2),
                      );
                },
                child: Text(
                  appLocalizationsOf(context).back,
                  style: ArDriveTypographyNew.of(context).paragraphLarge(
                    fontWeight: ArFontWeight.bold,
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
                    fontStyle: ArDriveTypographyNew.of(context).paragraphLarge(
                      fontWeight: ArFontWeight.bold,
                      color: Colors.white,
                    ),
                    isDisabled:
                        state is PaymentReviewLoadingQuote || !_emailIsValid,
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
                            ),
                          );
                    },
                  ),
                  mobile: (context) => ArDriveButton(
                    maxHeight: 44,
                    maxWidth: double.maxFinite,
                    text: appLocalizationsOf(context).pay,
                    fontStyle: ArDriveTypographyNew.of(context).paragraphLarge(
                      fontWeight: ArFontWeight.bold,
                      color: Colors.white,
                    ),
                    isDisabled:
                        state is PaymentReviewLoadingQuote || !_emailIsValid,
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
            style: ArDriveTypographyNew.of(context).paragraphNormal(
              fontWeight: ArFontWeight.bold,
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
                      style: ArDriveTypographyNew.of(context).paragraphNormal(
                        fontWeight: ArFontWeight.bold,
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

/// Styled quote timer bar with refresh button
class _QuoteTimerBar extends StatelessWidget {
  final DateTime expirationDate;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _QuoteTimerBar({
    required this.expirationDate,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 16,
            color: colors.themeFgMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, snapshot) {
                final remaining = expirationDate.difference(DateTime.now());
                final isExpired = remaining.isNegative;
                final minutes = remaining.inMinutes.abs();
                final seconds = (remaining.inSeconds % 60).abs();

                return Text(
                  isExpired
                      ? 'Quote expired'
                      : 'Quote updates in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: typography.paragraphSmall(
                    color: isExpired
                        ? colors.themeErrorDefault
                        : colors.themeFgMuted,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          ArDriveClickArea(
            child: GestureDetector(
              onTap: isLoading ? null : onRefresh,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.themeBgCanvas,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.themeBorderDefault),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.themeFgMuted,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 14,
                            color: colors.themeFgMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Refresh',
                            style: typography.paragraphSmall(
                              fontWeight: ArFontWeight.semiBold,
                              color: colors.themeFgMuted,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

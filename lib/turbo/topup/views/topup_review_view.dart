import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/turbo/topup/blocs/payment_review/payment_review_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
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
    final colors = theme.colors;
    final typography = ArDriveTypographyNew.of(context);

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
              current is PaymentReviewLoadingPaymentModel ||
              current is PaymentReviewInitial;
        },
        builder: (context, state) {
          if (state is PaymentReviewLoadingPaymentModel ||
              state is PaymentReviewInitial) {
            return const TurboTopupScaffold(
              child: SizedBox(
                height: 575,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }

          final loadedState = state as PaymentReviewPaymentModelLoaded;

          return TurboTopupScaffold(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with timer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Confirm Payment',
                      style: typography.heading5(
                        fontWeight: ArFontWeight.bold,
                        color: colors.themeFgDefault,
                      ),
                    ),
                    BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
                      builder: (context, state) {
                        if (state is PaymentReviewPaymentModelLoaded) {
                          return _QuoteTimerBar(
                            expirationDate: state.quoteExpirationDate,
                            isLoading: state is PaymentReviewLoadingQuote,
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
                  ],
                ),
                const SizedBox(height: 12),

                // Section 1: Paying With
                _PayingWithSection(
                  total: loadedState.total,
                  subTotal: loadedState.subTotal,
                  promoDiscount: loadedState.promoDiscount,
                ),
                const SizedBox(height: 12),

                // Section 2: You'll Receive
                _YoullReceiveSection(
                  creditsToReceive: loadedState.creditsWinc,
                  storageEstimate: loadedState.storageEstimate,
                  newBalance: loadedState.newBalance,
                  newBalanceStorage: loadedState.newBalanceStorage,
                ),
                const SizedBox(height: 12),

                // Email section
                _EmailSection(
                  textTheme: textTheme,
                  emailController: _emailController,
                  emailIsValid: _emailIsValid,
                  emailChecked: _emailChecked,
                  onEmailValidChanged: (valid) {
                    setState(() {
                      _emailIsValid = valid;
                      if (!valid) _emailChecked = false;
                    });
                  },
                  onEmailChanged: () {
                    if (!_hasAutomaticChecked && _emailIsValid) {
                      setState(() {
                        _emailChecked = true;
                        _hasAutomaticChecked = true;
                      });
                    }
                  },
                  onCheckChanged: (checked) {
                    setState(() {
                      _emailChecked = checked;
                    });
                  },
                ),
                const SizedBox(height: 12),

                // Terms notice
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'By continuing, you agree to the ',
                        style: typography.paragraphSmall(
                          color: colors.themeFgMuted,
                        ),
                      ),
                      TextSpan(
                        text: 'Terms of Service',
                        style: typography
                            .paragraphSmall(
                              color: colors.themeFgMuted,
                            )
                            .copyWith(
                              decoration: TextDecoration.underline,
                            ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => openUrl(
                                url: Resources.agreementLink,
                              ),
                      ),
                      TextSpan(
                        text: '.',
                        style: typography.paragraphSmall(
                          color: colors.themeFgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Buttons (fixed at bottom)
                _buildFooterButtons(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooterButtons(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colors;

    return ScreenTypeLayout.builder(
      mobile: (context) => Column(
        children: [
          SizedBox(
            width: double.maxFinite,
            child: BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
              builder: (context, state) {
                return ArDriveButton(
                  maxHeight: 48,
                  text: appLocalizationsOf(context).pay,
                  fontStyle: typography.paragraphLarge(
                    fontWeight: ArFontWeight.bold,
                    color: Colors.white,
                  ),
                  isDisabled: state is PaymentReviewLoadingQuote ||
                      !_emailIsValid ||
                      (state is PaymentReviewPaymentModelLoaded &&
                          DateTime.now().isAfter(state.quoteExpirationDate)),
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
                  onPressed: () => _handlePay(context, state),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          ArDriveClickArea(
            child: GestureDetector(
              onTap: () {
                context
                    .read<TurboTopupFlowBloc>()
                    .add(const TurboTopUpShowPaymentFormView(2));
              },
              child: Text(
                appLocalizationsOf(context).back,
                style: typography.paragraphLarge(
                  fontWeight: ArFontWeight.bold,
                  color: colors.themeFgMuted,
                ),
              ),
            ),
          ),
        ],
      ),
      desktop: (context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ArDriveClickArea(
            child: GestureDetector(
              onTap: () {
                context
                    .read<TurboTopupFlowBloc>()
                    .add(const TurboTopUpShowPaymentFormView(2));
              },
              child: Text(
                appLocalizationsOf(context).back,
                style: typography.paragraphLarge(
                  fontWeight: ArFontWeight.bold,
                  color: colors.themeFgMuted,
                ),
              ),
            ),
          ),
          BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
            builder: (context, state) {
              return ArDriveButton(
                maxHeight: 48,
                text: appLocalizationsOf(context).pay,
                fontStyle: typography.paragraphLarge(
                  fontWeight: ArFontWeight.bold,
                  color: Colors.white,
                ),
                isDisabled: state is PaymentReviewLoadingQuote ||
                    !_emailIsValid ||
                    (state is PaymentReviewPaymentModelLoaded &&
                        DateTime.now().isAfter(state.quoteExpirationDate)),
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
                onPressed: () => _handlePay(context, state),
              );
            },
          ),
        ],
      ),
    );
  }

  void _handlePay(BuildContext context, PaymentReviewState state) {
    if (state is PaymentReviewLoading) return;

    context.read<PaymentReviewBloc>().add(
          PaymentReviewFinishPayment(
            email: _emailController.text,
            userAcceptedToReceiveEmails: _emailChecked,
          ),
        );
  }
}

// ============================================
// Section 1: Paying With (Credit Card)
// ============================================

class _PayingWithSection extends StatelessWidget {
  final String total;
  final String? subTotal;
  final String? promoDiscount;

  const _PayingWithSection({
    required this.total,
    this.subTotal,
    this.promoDiscount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    // Calculate discount percentage
    int? discountPercent;
    if (promoDiscount != null && subTotal != null) {
      final sub = double.tryParse(subTotal!) ?? 0;
      final tot = double.tryParse(total) ?? 0;
      if (sub > 0 && tot < sub) {
        discountPercent = ((1 - (tot / sub)) * 100).round();
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Credit card info row with label
          Row(
            children: [
              // Card icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.themeBgSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.themeBorderDefault),
                ),
                child: Icon(
                  Icons.credit_card,
                  color: colors.themeFgDefault,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              // Card type
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Credit Card',
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.themeFgDefault,
                      ),
                    ),
                    Text(
                      'Secure payment via Stripe',
                      style: typography.paragraphSmall(
                        color: colors.themeFgMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Amount on the right
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '\$${NumberFormat('#,##0.00').format(double.tryParse(total) ?? 0)}',
                        style: typography.heading5(
                          fontWeight: ArFontWeight.bold,
                          color: colors.themeFgDefault,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'USD',
                        style: typography.paragraphSmall(
                          fontWeight: ArFontWeight.semiBold,
                          color: colors.themeFgMuted,
                        ),
                      ),
                    ],
                  ),
                  if (subTotal != null && discountPercent != null)
                    Text(
                      'was \$${NumberFormat('#,##0.00').format(double.tryParse(subTotal!) ?? 0)}',
                      style: typography
                          .paragraphSmall(
                            color: colors.themeFgMuted,
                          )
                          .copyWith(decoration: TextDecoration.lineThrough),
                    ),
                ],
              ),
            ],
          ),

          // Promo/discount badge
          if (promoDiscount != null && discountPercent != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.themeSuccessSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_offer,
                    size: 14,
                    color: colors.themeSuccessDefault,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$discountPercent% off applied',
                    style: typography.paragraphSmall(
                      fontWeight: ArFontWeight.semiBold,
                      color: colors.themeSuccessDefault,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================
// Section 2: You'll Receive
// ============================================

class _YoullReceiveSection extends StatelessWidget {
  final BigInt creditsToReceive;
  final String storageEstimate;
  final BigInt newBalance;
  final String newBalanceStorage;

  const _YoullReceiveSection({
    required this.creditsToReceive,
    required this.storageEstimate,
    required this.newBalance,
    required this.newBalanceStorage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Row(
        children: [
          // Credits to receive (left side)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "YOU'LL RECEIVE",
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.themeFgMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      convertWinstonToLiteralString(creditsToReceive),
                      style: typography.heading5(
                        fontWeight: ArFontWeight.bold,
                        color: colors.themeSuccessDefault,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'credits',
                      style: typography.paragraphSmall(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.themeFgMuted,
                      ),
                    ),
                  ],
                ),
                Text(
                  storageEstimate,
                  style: typography.paragraphSmall(
                    color: colors.themeFgMuted,
                  ),
                ),
              ],
            ),
          ),
          // Vertical divider
          Container(
            width: 1,
            height: 50,
            color: colors.themeBorderDefault,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          // New balance (right side)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEW BALANCE',
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.themeFgMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${convertWinstonToLiteralString(newBalance)} credits',
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.themeFgDefault,
                  ),
                ),
                Text(
                  newBalanceStorage,
                  style: typography.paragraphSmall(
                    color: colors.themeFgMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Email Section
// ============================================

class _EmailSection extends StatelessWidget {
  final ArDriveThemeData textTheme;
  final TextEditingController emailController;
  final bool emailIsValid;
  final bool emailChecked;
  final void Function(bool valid) onEmailValidChanged;
  final VoidCallback onEmailChanged;
  final void Function(bool checked) onCheckChanged;

  const _EmailSection({
    required this.textTheme,
    required this.emailController,
    required this.emailIsValid,
    required this.emailChecked,
    required this.onEmailValidChanged,
    required this.onEmailChanged,
    required this.onCheckChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocalizationsOf(context).leaveAnEmailToReceiveAReceipt,
            style: typography.paragraphSmall(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeFgDefault,
            ),
          ),
          const SizedBox(height: 12),
          ArDriveTheme(
            key: const ValueKey('turbo_payment_form'),
            themeData: textTheme,
            child: ArDriveTextField(
              validator: (s) {
                if (s == null || s.isEmpty || isEmailValid(s)) {
                  onEmailValidChanged(true);
                  return null;
                }
                onEmailValidChanged(false);
                return appLocalizationsOf(context).pleaseEnterAValidEmail;
              },
              controller: emailController,
              onChanged: (s) => onEmailChanged(),
            ),
          ),
          const SizedBox(height: 12),
          ArDriveCheckBox(
            isDisabled: !emailIsValid || emailController.text.isEmpty,
            key: ValueKey(
                '${emailIsValid && emailChecked}${emailController.text}'),
            title:
                appLocalizationsOf(context).keepMeUpToDateOnNewsAndPromotions,
            titleStyle: typography.paragraphSmall(
              color: colors.themeFgDefault,
            ),
            onChange: onCheckChanged,
            checked:
                emailIsValid && emailChecked && emailController.text.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

// ============================================
// Quote Timer Bar
// ============================================

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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.schedule,
          size: 14,
          color: colors.themeFgMuted,
        ),
        const SizedBox(width: 6),
        StreamBuilder(
          stream: Stream.periodic(const Duration(seconds: 1)),
          builder: (context, snapshot) {
            final remaining = expirationDate.difference(DateTime.now());
            final isExpired = remaining.isNegative;
            final minutes = remaining.inMinutes.abs();
            final seconds = (remaining.inSeconds % 60).abs();

            return Text(
              isExpired
                  ? 'Quote expired'
                  : 'Price valid for ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              style: typography.paragraphSmall(
                color:
                    isExpired ? colors.themeErrorDefault : colors.themeFgMuted,
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: isLoading ? null : onRefresh,
          child: isLoading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.themeFgMuted,
                  ),
                )
              : Icon(
                  Icons.refresh,
                  size: 16,
                  color: colors.themeFgMuted,
                ),
        ),
      ],
    );
  }
}

// ============================================
// Helpers
// ============================================

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

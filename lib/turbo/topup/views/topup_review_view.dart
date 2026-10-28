import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/turbo/topup/blocs/payment_review/payment_review_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/components/quote_timer.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

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
    final colors = theme.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    // custom theme for the text fields on the top-up form
    final textTheme = theme.copyWith(
      textFieldTheme: theme.textFieldTheme.copyWith(
        inputBackgroundColor: theme.colorTokens.containerL3,
        labelColor: theme.colorTokens.textHigh,
        requiredLabelColor: theme.colorTokens.textHigh,
        inputTextStyle: theme.textFieldTheme.inputTextStyle.copyWith(
          color: theme.colorTokens.textMid,
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 8,
        ),
        labelStyle: TextStyle(
          color: theme.colorTokens.textHigh,
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
                newBalanceCredits: state.newBalanceCredits,
                newBalanceStorage: state.newBalanceStorage,
              ));
        }
        // Errors are shown in the review itself: a dialog over this dialog
        // took the person out of the screen they were on.
      },
      child: BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
        buildWhen: (previous, current) {
          return current is PaymentReviewPaymentModelLoaded ||
              current is PaymentReviewLoadingPaymentModel ||
              current is PaymentReviewErrorLoadingPaymentModel ||
              current is PaymentReviewInitial;
        },
        builder: (context, state) {
          if (state is PaymentReviewErrorLoadingPaymentModel) {
            return TurboTopupScaffold(
              title: 'Confirm payment',
              actions: [
                ModalAction.dismiss(
                  title: appLocalizationsOf(context).back,
                  action: () => context
                      .read<TurboTopupFlowBloc>()
                      .add(const TurboTopUpShowPaymentFormView(2)),
                ),
                ModalAction(
                  title: appLocalizationsOf(context).tryAgain,
                  action: () => context
                      .read<PaymentReviewBloc>()
                      .add(PaymentReviewLoadPaymentModel()),
                ),
              ],
              child: ArDriveNotice(
                type: ArDriveNoticeType.error,
                message: turboErrorMessage(
                  context,
                  TurboErrorType.fetchPaymentIntentFailed,
                ),
              ),
            );
          }

          if (state is PaymentReviewLoadingPaymentModel ||
              state is PaymentReviewInitial) {
            return const TurboTopupScaffold(
              title: 'Confirm payment',
              child: SizedBox(
                height: 400,
                child: Center(
                  child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
                ),
              ),
            );
          }

          final loadedState = state as PaymentReviewPaymentModelLoaded;

          // Rebuilt on every payment state, so the action row follows the
          // quote and the payment while the sections keep the loaded model.
          return BlocBuilder<PaymentReviewBloc, PaymentReviewState>(
            builder: (context, payState) => TurboTopupScaffold(
              title: 'Confirm payment',
              actions: _actions(context, payState),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The quote's timer, with its refresh.
                  Align(
                    alignment: Alignment.centerRight,
                    child: QuoteTimer(
                      expiresAt: loadedState.quoteExpirationDate,
                      isLoading: payState is PaymentReviewLoadingQuote,
                      // Redraws the actions so Confirm & Pay turns off.
                      onExpired: () {
                        if (mounted) setState(() {});
                      },
                      onRefresh: () {
                        context
                            .read<PaymentReviewBloc>()
                            .add(PaymentReviewRefreshQuote());
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // A payment that failed: what happened, and the way back
                  // to the card details.
                  if (payState is PaymentReviewPaymentError) ...[
                    ArDriveNotice(
                      type: ArDriveNoticeType.error,
                      message: turboErrorMessage(context, payState.errorType),
                      actionLabel: 'Edit card details',
                      onAction: () => context
                          .read<TurboTopupFlowBloc>()
                          .add(const TurboTopUpShowPaymentFormView(2)),
                    ),
                    const SizedBox(height: 12),
                  ],

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
                      style: typography.paragraphSmall(color: colors.textMid),
                      children: [
                        const TextSpan(
                            text: 'By continuing, you agree to the '),
                        ArDriveLink.span(
                          text: 'Terms of Service',
                          external: true,
                          style: typography.paragraphSmall(),
                          onTap: () => openUrl(url: Resources.agreementLink),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Back, and Confirm & Pay: disabled while the quote refreshes, without a
  /// valid email or once the quote has expired, and saying so while paying.
  List<ModalAction> _actions(BuildContext context, PaymentReviewState state) {
    final isPaying = state is PaymentReviewLoading;
    final quoteExpired = state is PaymentReviewPaymentModelLoaded &&
        DateTime.now().isAfter(state.quoteExpirationDate);

    return [
      ModalAction.dismiss(
        title: appLocalizationsOf(context).back,
        action: () => context
            .read<TurboTopupFlowBloc>()
            .add(const TurboTopUpShowPaymentFormView(2)),
      ),
      ModalAction(
        title: isPaying ? 'Processing...' : 'Confirm & Pay',
        isEnable: !isPaying &&
            state is! PaymentReviewLoadingQuote &&
            // After a failure the card details go back to the form.
            state is! PaymentReviewPaymentError &&
            _emailIsValid &&
            !quoteExpired,
        action: () => _handlePay(context, state),
      ),
    ];
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
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
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.strokeMid),
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
                  color: colors.containerRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.strokeMid),
                ),
                child: Icon(
                  Icons.credit_card,
                  color: colors.textHigh,
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
                      'Credit card',
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.textHigh,
                      ),
                    ),
                    Text(
                      'Secure payment via Stripe',
                      style: typography.paragraphSmall(
                        color: colors.textMid,
                      ),
                    ),
                  ],
                ),
              ),
              // Amount on the right
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // The amount paid is this card's figure.
                  // One text, so the unit wraps under the figure rather than
                  // overflowing a narrow column.
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                            text:
                                '\$${NumberFormat('#,##0.00').format(double.tryParse(total) ?? 0)}',
                            style: typography.heading2(
                              fontWeight: ArFontWeight.light,
                              color: colors.textHigh,
                            )),
                        const TextSpan(text: ' '),
                        TextSpan(
                            text: 'USD',
                            style: typography.paragraphSmall(
                              fontWeight: ArFontWeight.semiBold,
                              color: colors.textMid,
                            )),
                      ],
                    ),
                  ),
                  if (subTotal != null && discountPercent != null)
                    Text(
                      'was \$${NumberFormat('#,##0.00').format(double.tryParse(subTotal!) ?? 0)}',
                      style: typography
                          .paragraphSmall(
                            color: colors.textMid,
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
            ArDriveTag(
              type: ArDriveTagType.success,
              icon: Icons.local_offer,
              text: '$discountPercent% off applied',
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.strokeMid),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    color: colors.textMid,
                  ),
                ),
                const SizedBox(height: 4),
                // The credits bought are this card's figure.
                // One text, so the unit wraps under the figure rather than
                // overflowing a narrow column.
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: convertWinstonToLiteralString(creditsToReceive),
                          style: typography.heading2(
                            fontWeight: ArFontWeight.light,
                            color: colors.textHigh,
                          )),
                      const TextSpan(text: ' '),
                      TextSpan(
                          text: 'credits',
                          style: typography.paragraphSmall(
                            fontWeight: ArFontWeight.semiBold,
                            color: colors.textMid,
                          )),
                    ],
                  ),
                ),
                Text(
                  storageEstimate,
                  style: typography.paragraphSmall(
                    color: colors.textMid,
                  ),
                ),
              ],
            ),
          ),
          // Vertical divider
          Container(
            width: 1,
            height: 50,
            color: colors.strokeMid,
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
                    color: colors.textMid,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${convertWinstonToLiteralString(newBalance)} credits',
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.textHigh,
                  ),
                ),
                Text(
                  newBalanceStorage,
                  style: typography.paragraphSmall(
                    color: colors.textMid,
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.strokeMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appLocalizationsOf(context).leaveAnEmailToReceiveAReceipt,
            style: typography.paragraphSmall(
              fontWeight: ArFontWeight.semiBold,
              color: colors.textHigh,
            ),
          ),
          const SizedBox(height: 12),
          ArDriveTheme(
            key: const ValueKey('turbo_payment_form'),
            themeData: textTheme,
            child: ArDriveTextFieldNew(
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
              color: colors.textHigh,
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
                if (state is PaymentReviewLoadingQuote) const ArDriveSpinner(),
                if (state is! PaymentReviewLoadingQuote)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: ArDriveIcons.refresh(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colorTokens
                          .textHigh,
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
                            .colorTokens
                            .textHigh,
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

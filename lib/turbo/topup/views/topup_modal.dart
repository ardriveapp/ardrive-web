import 'package:animations/animations.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/crypto_price_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive/turbo/topup/blocs/payment_form/payment_form_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/payment_review/payment_review_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/topup_estimation_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/unified_topup/unified_topup_bloc.dart';
import 'package:ardrive/turbo/topup/components/payment_method_selector.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/topup_payment_form.dart';
import 'package:ardrive/turbo/topup/views/topup_review_view.dart';
import 'package:ardrive/turbo/topup/views/topup_success_view.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/turbo/topup/views/unified/unified_crypto_flow.dart';
import 'package:ardrive/turbo/topup/views/unified_pay_view.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide PaymentMethod;

void showTurboTopupModal(BuildContext context, {Function()? onSuccess}) {
  final activityTracker = context.read<ActivityTracker>();
  final sessionManager = TurboSessionManager();
  final appConfig = context.read<ConfigService>().config;

  final costCalculator = TurboCostCalculator(
    paymentService: context.read<PaymentService>(),
  );

  final balanceRetriever = TurboBalanceRetriever(
    paymentService: context.read<PaymentService>(),
  );

  final priceEstimator = TurboPriceEstimator(
    wallet: context.read<ArDriveAuth>().currentUser.wallet,
    paymentService: context.read<PaymentService>(),
    costCalculator: costCalculator,
    shouldStartOnPriceEstimateChange: true,
  );

  final turboPaymentProvider = StripePaymentProvider(
    paymentService: context.read<PaymentService>(),
    stripe: Stripe.instance,
  );

  final turboSupportedCountriesRetriever = TurboSupportedCountriesRetriever(
      paymentService: context.read<PaymentService>());

  final turbo = Turbo(
    sessionManager: sessionManager,
    costCalculator: costCalculator,
    balanceRetriever: balanceRetriever,
    priceEstimator: priceEstimator,
    paymentProvider: turboPaymentProvider,
    wallet: context.read<ArDriveAuth>().currentUser.wallet,
    supportedCountriesRetriever: turboSupportedCountriesRetriever,
  );

  initializeStripe(appConfig);

  activityTracker.setToppingUp(true);

  PlausibleEventTracker.trackPageview(page: PlausiblePageView.turboTopUpModal);

  showAnimatedDialogWithBuilder(
    context,
    builder: (modalContext) => MultiBlocProvider(
      providers: [
        RepositoryProvider<Turbo>(create: (context) => turbo),
        BlocProvider(
          create: (context) => TurboTopupFlowBloc(
            context.read<Turbo>(),
          )..add(const TurboTopUpShowEstimationView()),
        ),
        BlocProvider(
          create: (context) => TurboTopUpEstimationBloc(
            turbo: context.read<Turbo>(),
          )..add(LoadInitialData()),
        ),
        BlocProvider(
          create: (context) => UnifiedTopupBloc(
            turbo: context.read<Turbo>(),
            priceService: CryptoPriceService(httpClient: ArDriveHTTP()),
          )..add(const UnifiedTopupStarted()),
        ),
      ],
      child: TurboModal(parentContext: modalContext),
    ),
    barrierDismissible: false,
    barrierColor:
        ArDriveTheme.of(context).themeData.colors.shadow.withOpacity(0.9),
  ).then((value) {
    logger.d('Turbo modal closed with value: ${turbo.paymentStatus}');

    if (turbo.paymentStatus == PaymentStatus.success) {
      logger.d('Turbo payment success');
      PlausibleEventTracker.trackPageview(
          page: PlausiblePageView.turboTopUpSuccess);

      onSuccess?.call();
    } else {
      logger.d('Turbo payment error');
      PlausibleEventTracker.trackPageview(
          page: PlausiblePageView.turboTopUpCancel);
    }

    turbo.dispose();
  }).whenComplete(() {
    activityTracker.setToppingUp(false);
  });
}

class TurboModal extends StatefulWidget {
  final BuildContext parentContext;

  const TurboModal({
    super.key,
    required this.parentContext,
  });

  @override
  State<TurboModal> createState() => _TurboModalState();
}

class _TurboModalState extends State<TurboModal> with TickerProviderStateMixin {
  late final AnimationController _opacityController;
  bool isOpacityTransitionDelayed = false;

  // Keep PaymentFormBloc alive across payment form and review views
  // so the Stripe CardField element stays mounted with card data
  PaymentFormBloc? _paymentFormBloc;

  @override
  initState() {
    super.initState();
    _opacityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  dispose() {
    _opacityController.dispose();
    _paymentFormBloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TurboTopupFlowBloc, TurboTopupFlowState>(
      listener: (context, state) {
        if (state is TurboTopupFlowShowingSuccessView) {
          Navigator.of(context).pop();
          _showSuccessDialog(
            amountPaid: state.amountPaid,
            creditsReceived: state.creditsReceived,
            storageEstimate: state.storageEstimate,
            newBalanceStorage: state.newBalanceStorage,
          );
        } else if (state is TurboTopupFlowShowingErrorView) {
          _showErrorDialog(state.errorType,
              parentContext: widget.parentContext);
        }
      },
      child: ArDriveModal(
        contentPadding: EdgeInsets.zero,
        content: _content(),
        constraints: BoxConstraints(
          maxWidth: 575,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
      ),
    );
  }

  TurboTopupFlowState? _previousState;

  Widget _content() {
    return BlocConsumer<TurboTopupFlowBloc, TurboTopupFlowState>(
      listenWhen: (previous, current) {
        // Listen when going back to estimation view (from payment form)
        return current is TurboTopupFlowShowingEstimationView &&
            previous is! TurboTopupFlowShowingEstimationView &&
            previous is! TurboTopupFlowInitial;
      },
      listener: (context, state) {
        // When going back to estimation view, restore the unified bloc state
        if (state is TurboTopupFlowShowingEstimationView) {
          context
              .read<UnifiedTopupBloc>()
              .add(const UnifiedTopupBackToLoaded());
        }
      },
      buildWhen: (previous, current) {
        return previous.runtimeType != current.runtimeType;
      },
      builder: (context, state) {
        Widget view;

        if (state is TurboTopupFlowShowingEstimationView) {
          // Unified flow is the only supported flow
          view = UnifiedPayView(
            onContinue: (method, token, amount) {
              _handleUnifiedContinue(context, method, token, amount);
            },
          );
        } else if (state is TurboTopupFlowShowingPaymentFormView) {
          PlausibleEventTracker.trackPageview(
            page: PlausiblePageView.turboPaymentDetails,
          );
          // Create PaymentFormBloc if not exists, or reuse existing one
          // This keeps the Stripe CardField mounted with card data
          _paymentFormBloc ??= PaymentFormBloc(
            context.read<Turbo>(),
            state.priceEstimate,
          )..add(PaymentFormLoadSupportedCountries());

          view = Stack(
            children: [
              BlocProvider<PaymentFormBloc>.value(
                key: const ValueKey('payment_form'),
                value: _paymentFormBloc!,
                child: Container(
                  key: const ValueKey('payment_form'),
                  color: Colors.transparent,
                  child: const Opacity(
                    key: ValueKey('payment_form'),
                    opacity: 1,
                    child: TurboPaymentFormView(),
                  ),
                ),
              ),
            ],
          );
        } else if (state is TurboTopupFlowShowingPaymentReviewView) {
          PlausibleEventTracker.trackPageview(
            page: PlausiblePageView.turboPurchaseReview,
          );
          // Reuse the existing PaymentFormBloc to keep CardField mounted
          // with the card data entered by the user
          _paymentFormBloc ??= PaymentFormBloc(
            context.read<Turbo>(),
            state.priceEstimate,
          )..add(PaymentFormLoadSupportedCountries());

          view = Stack(
            children: [
              BlocProvider<PaymentFormBloc>.value(
                key: const ValueKey('payment_form'),
                value: _paymentFormBloc!,
                child: Container(
                  key: const ValueKey('payment_form'),
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
                  child: const Opacity(
                    key: ValueKey('payment_form'),
                    opacity: 0,
                    child: TurboPaymentFormView(),
                  ),
                ),
              ),
              BlocProvider<PaymentReviewBloc>(
                create: (context) => PaymentReviewBloc(
                  context.read<Turbo>(),
                  state.priceEstimate,
                )..add(PaymentReviewLoadPaymentModel()),
                child: Container(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
                  child: const TurboReviewView(),
                ),
              ),
            ],
          );
        } else if (state is TurboTopupFlowShowingCryptoView) {
          // Crypto payment flow - embedded in the same modal
          view = UnifiedCryptoFlow(
            fiatAmount: state.amount,
            preselectedToken: state.token,
            currentTurboBalance: state.currentTurboBalance,
            currentBalanceStorage: state.currentBalanceStorage,
            creditsToReceive: state.creditsToReceive,
            newBalanceStorage: state.newBalanceStorage,
            onSuccess: () {
              Navigator.of(context).pop();
            },
            onCancel: () {
              Navigator.of(context).pop();
            },
            onBack: () {
              // Go back to payment method selection (same as card flow)
              context
                  .read<TurboTopupFlowBloc>()
                  .add(const TurboTopUpShowEstimationView());
            },
          );
        } else {
          view = Container(
            height: 575,
            color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (_previousState?.runtimeType != state.runtimeType) {
          isOpacityTransitionDelayed = true;

          _opacityController.reset();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 300)).then((_) {
              if (mounted) _opacityController.forward();
            });
          });
        }

        _previousState = state;

        final animation = Tween<double>(
          begin: 0.01,
          end: 1.0,
        ).animate(
          CurvedAnimation(parent: _opacityController, curve: Curves.easeInOut),
        );

        return Container(
          color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return Opacity(
                  opacity: isOpacityTransitionDelayed ? animation.value : 1,
                  child: child,
                );
              },
              child: view,
            ),
          ),
        );
      },
    );
  }

  /// Handles the continue action from the unified pay view.
  ///
  /// For card payments: transitions to the payment form view.
  /// For crypto payments: opens the crypto modal.
  Future<void> _handleUnifiedContinue(
    BuildContext context,
    PaymentMethod method,
    CryptoToken? token,
    double amount,
  ) async {
    if (method == PaymentMethod.card) {
      // For card payments, go to the payment form view
      // First compute the price estimate directly to ensure turbo._currentAmount is set
      // before we transition to the payment form (avoids race condition)
      final turbo = context.read<Turbo>();
      try {
        await turbo.computePriceEstimate(
          currentAmount: amount,
          currentCurrency: 'usd',
          currentDataUnit: FileSizeUnit.gigabytes,
          promoCode: turbo.promoCode,
        );
        // Also update the estimation bloc for consistency
        if (context.mounted) {
          context
              .read<TurboTopUpEstimationBloc>()
              .add(FiatAmountSelected(amount));
          // Then transition to payment form (step 2 in the flow)
          context
              .read<TurboTopupFlowBloc>()
              .add(const TurboTopUpShowPaymentFormView(2));
        }
      } catch (e) {
        logger.e('Error computing price estimate: $e');
        if (context.mounted) {
          // Show error state - user can retry from the unified pay view
          context
              .read<TurboTopupFlowBloc>()
              .add(const TurboTopUpShowErrorView(
                TurboErrorType.fetchEstimationInformationFailed,
              ));
        }
      }
    } else if (method == PaymentMethod.crypto && token != null) {
      // For crypto payments, get balance data from unified topup bloc
      final unifiedState = context.read<UnifiedTopupBloc>().state;
      BigInt currentBalance = BigInt.zero;
      String currentBalanceStorage = '0';
      BigInt creditsToReceive = BigInt.zero;
      String newBalanceStorage = '0';

      if (unifiedState is UnifiedTopupLoaded) {
        currentBalance = unifiedState.currentBalance;
        currentBalanceStorage = unifiedState.currentBalanceStorage;
        creditsToReceive = unifiedState.creditsToReceive;
        newBalanceStorage = unifiedState.newBalanceStorage;
      } else if (unifiedState is UnifiedTopupReadyToContinue) {
        currentBalance = unifiedState.currentBalance;
        currentBalanceStorage = unifiedState.currentBalanceStorage;
        creditsToReceive = unifiedState.creditsToReceive;
        newBalanceStorage = unifiedState.newBalanceStorage;
      }

      // Transition to crypto flow view with balance data for checkout display
      // Note: currentBalanceStorage and newBalanceStorage already include units from dynamic formatting
      context.read<TurboTopupFlowBloc>().add(TurboTopUpShowCryptoView(
            token: token,
            amount: amount,
            currentTurboBalance: currentBalance,
            currentBalanceStorage: currentBalanceStorage,
            creditsToReceive: creditsToReceive,
            newBalanceStorage: newBalanceStorage,
          ));
    }
  }

  void _showSuccessDialog({
    String? amountPaid,
    String? creditsReceived,
    String? storageEstimate,
    String? newBalanceStorage,
  }) {
    // Use parentContext since the current context is invalid after pop()
    showArDriveDialog(
      widget.parentContext,
      content: ArDriveStandardModal(
        width: 575,
        content: Hero(
          tag: 'turbo_success',
          child: TurboSuccessView(
            amountPaid: amountPaid,
            creditsReceived: creditsReceived,
            storageEstimate: storageEstimate,
            newBalanceStorage: newBalanceStorage,
          ),
        ),
      ),
      barrierDismissible: false,
      barrierColor: ArDriveTheme.of(widget.parentContext)
          .themeData
          .colors
          .shadow
          .withOpacity(0.9),
    );
  }

  void _showErrorDialog(
    TurboErrorType type, {
    required BuildContext parentContext,
  }) {
    showAnimatedDialogWithBuilder(
      context,
      builder: (modalContext) => ArDriveStandardModal(
        width: 575,
        content: TurboErrorView(
          errorType: type,
          onDismiss: () {
            logger.d('clicked dismiss on error modal');
            Navigator.of(modalContext).pop();
          },
          onTryAgain: () {
            logger.d('clicked try again on error modal');
            Navigator.of(modalContext).pop();
            Navigator.of(context).pop();

            showTurboTopupModal(parentContext);
          },
        ),
      ),
      barrierDismissible: false,
      barrierColor:
          ArDriveTheme.of(context).themeData.colors.shadow.withOpacity(0.9),
    );
  }
}

class PaymentFlowView extends StatelessWidget {
  final Widget view;

  const PaymentFlowView(this.view, {super.key});

  @override
  Widget build(BuildContext context) {
    return PageTransitionSwitcher(
      transitionBuilder: (
        Widget child,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: SharedAxisTransitionType.horizontal,
          child: child,
        );
      },
      child: view,
    );
  }
}

class PaymentFlowBackView extends StatelessWidget {
  final Widget view;

  const PaymentFlowBackView(this.view, {super.key});

  @override
  Widget build(BuildContext context) {
    return PageTransitionSwitcher(
      reverse: true,
      transitionBuilder: (
        Widget child,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: SharedAxisTransitionType.horizontal,
          child: child,
        );
      },
      child: view,
    );
  }
}

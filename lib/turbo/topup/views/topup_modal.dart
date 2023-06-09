import 'package:animations/animations.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/top_up_dialog.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/turbo/topup/blocs/payment_form/payment_form_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/payment_review/payment_review_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/topup_estimation_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/views/topup_payment_form.dart';
import 'package:ardrive/turbo/topup/views/topup_review_view.dart';
import 'package:ardrive/turbo/topup/views/topup_success_view.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void showTurboModal(BuildContext context) {
  final turbo = Turbo(
    paymentService: context.read<PaymentService>(),
    wallet: context.read<ArDriveAuth>().currentUser!.wallet,
  );
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
      ],
      child: TurboModal(parentContext: modalContext),
    ),
    barrierDismissible: false,
    barrierColor:
        ArDriveTheme.of(context).themeData.colors.shadow.withOpacity(0.9),
  ).then((value) {
    logger.d('Turbo modal closed');
    turbo.dispose();
  });
}

class TurboModal extends StatefulWidget {
  const TurboModal({super.key, required this.parentContext});

  final BuildContext parentContext;

  @override
  State<TurboModal> createState() => _TurboModalState();
}

class _TurboModalState extends State<TurboModal> with TickerProviderStateMixin {
  late final AnimationController _opacityController;
  bool isOpacityTransitionDelayed = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TurboTopupFlowBloc, TurboTopupFlowState>(
      listener: (context, state) {
        if (state is TurboTopupFlowShowingSuccessView) {
          Navigator.of(context).pop();
          _showSuccessDialog();
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
    return BlocBuilder<TurboTopupFlowBloc, TurboTopupFlowState>(
      buildWhen: (previous, current) {
        return previous.runtimeType != current.runtimeType;
      },
      builder: (context, state) {
        Widget view;

        if (state is TurboTopupFlowShowingEstimationView) {
          view = const TopUpEstimationView();
        } else if (state is TurboTopupFlowShowingPaymentFormView) {
          view = Stack(
            children: [
              BlocProvider<PaymentFormBloc>(
                key: const ValueKey('payment_form'),
                create: (context) => PaymentFormBloc(
                  context.read<Turbo>(),
                  state.priceEstimate,
                ),
                child: const TurboPaymentFormView(
                  key: ValueKey('payment_form'),
                ),
              ),
            ],
          );
        } else if (state is TurboTopupFlowShowingPaymentReviewView) {
          view = Stack(
            children: [
              BlocProvider<PaymentFormBloc>(
                key: const ValueKey('payment_form'),
                create: (context) => PaymentFormBloc(
                  context.read<Turbo>(),
                  state.priceEstimate,
                ),
                child: const TurboPaymentFormView(
                  key: ValueKey('payment_form'),
                ),
              ),
              BlocProvider<PaymentReviewBloc>(
                create: (context) => PaymentReviewBloc(
                  context.read<Turbo>(),
                  state.priceEstimate,
                  state.paymentUserInformation,
                ),
                child: Container(
                    color:
                        ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
                    child: const TurboReviewView()),
              ),
            ],
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

        return Container(
          color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: FadeTransition(
              opacity: _opacityController,
              child: view,
            ),
          ),
        );
      },
    );
  }

  void _showSuccessDialog() {
    showAnimatedDialog(
      context,
      content: const ArDriveStandardModal(
        width: 575,
        content: Hero(tag: 'turbo_success', child: TurboSuccessView()),
      ),
      barrierDismissible: false,
      barrierColor:
          ArDriveTheme.of(context).themeData.colors.shadow.withOpacity(0.9),
    );
  }

  void _showErrorDialog(TurboErrorType type,
      {required BuildContext parentContext}) {
    showAnimatedDialogWithBuilder(
      context,
      builder: (modalContext) => ArDriveStandardModal(
        width: 575,
        content: TurboErrorView(
          errorType: type,
          onDismiss: () {
            logger.d('dismiss');
            Navigator.of(modalContext).pop();
          },
          onTryAgain: () {
            logger.d('try again');
            Navigator.of(modalContext).pop();
            Navigator.of(context).pop();

            showTurboModal(parentContext);
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

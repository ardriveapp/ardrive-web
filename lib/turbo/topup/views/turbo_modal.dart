import 'package:animations/animations.dart';
import 'package:ardrive/components/top_up_dialog.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/views/turbo_payment_form.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void showTurboModal(BuildContext context) {
  showAnimatedDialog(
    context,
    content: BlocProvider(
      create: (context) =>
          TurboTopupFlowBloc()..add(const TurboTopUpShowEstimationView()),
      child: const TurboModal(),
    ),
    barrierDismissible: false,
    barrierColor:
        ArDriveTheme.of(context).themeData.colors.shadow.withOpacity(0.9),
  );
}

class TurboModal extends StatefulWidget {
  const TurboModal({super.key});

  @override
  State<TurboModal> createState() => _TurboModalState();
}

class _TurboModalState extends State<TurboModal> {
  @override
  Widget build(BuildContext context) {
    return ArDriveModal(
      hasCloseButton: true,
      contentPadding: EdgeInsets.zero,
      content: Container(
        color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
        child: BlocBuilder<TurboTopupFlowBloc, TurboTopupFlowState>(
          builder: (context, state) {
            Widget view;
            if (state is TurboTopupFlowShowingEstimationView) {
              view = const TopUpEstimationView();
            } else if (state is TurboTopupFlowShowingPaymentFormView) {
              view = const TurboPaymentFormView();
            } else {
              view = Container(
                color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                var begin = state.isMovingForward
                    ? const Offset(1.0, 0.0)
                    : const Offset(-1.0, 0.0);
                var end = Offset.zero;
                var tween = Tween(begin: begin, end: end)
                    .chain(CurveTween(curve: Curves.ease));

                return SlideTransition(
                  position: animation.drive(tween),
                  child: Container(
                    color:
                        ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
                    child: child,
                  ),
                );
              },
              child: view,
            );
          },
        ),
      ),
      constraints: BoxConstraints(
        maxWidth: 575,
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
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

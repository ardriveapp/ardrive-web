import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToHide(
  BuildContext context,
) async {
  logger.d('Prompting to hide');
  return showAnimatedDialog(
    context,
    barrierDismissible: false,
    content: const HideDialog(),
  );
}

class HideDialog extends StatelessWidget {
  const HideDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HideBloc, HideState>(
      listener: (context, state) {
        if (state is SuccessHideState) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        return ArDriveStandardModal(
          title: _buildTitle(context, state),
          content: _buildContent(context, state),
          actions: _buildActions(context, state),
        );
      },
    );
  }

  String _buildTitle(
    BuildContext context,
    HideState state,
  ) {
    if (state is ConfirmingHideState) {
      final hideAction = state.hideAction;
      switch (hideAction) {
        case HideAction.hideFile:
          return 'Hide file?'; // TODO: localize
        case HideAction.hideFolder:
          return 'Hide folder?'; // TODO: localize
        case HideAction.unhideFile:
          return 'Unhide file?'; // TODO: localize
        case HideAction.unhideFolder:
          return 'Unhide folder?'; // TODO: localize
      }
    } else if (state is PreparingAndSigningHideState) {
      return 'Preparing and signing transactions'; // TODO: localize
    } else if (state is UploadingHideState) {
      return 'Uploading...'; // TODO: localize
    } else {
      return ''; // TODO: localize
    }
  }

  Widget _buildContent(
    BuildContext context,
    HideState state,
  ) {
    if (state is ConfirmingHideState) {
      return _buildConfirmingContent(context, state);
    } else if (state is PreparingAndSigningHideState) {
      return _buildPreparingAndSigningContent(context);
    } else if (state is UploadingHideState) {
      return _buildUploadingContent(context);
    } else {
      return const SizedBox();
    }
  }

  List<ModalAction> _buildActions(
    BuildContext context,
    HideState state,
  ) {
    if (state is ConfirmingHideState) {
      return [
        ModalAction(
          title: 'Cancel', // TODO: localize
          action: () {
            Navigator.of(context).pop();
          },
        ),
        ModalAction(
          title: 'Confirm', // TODO: localize
          action: () {
            context.read<HideBloc>().add(
                  const ConfirmUploadEvent(),
                );
          },
        ),
      ];
    } else {
      return [];
    }
  }

  Widget _buildConfirmingContent(
    BuildContext context,
    ConfirmingHideState state,
  ) {
    return Column(
      children: [
        if (state.isFreeThanksToTurbo) ...{
          Text(
            appLocalizationsOf(context).freeTurboTransaction,
            style: ArDriveTypography.body.buttonNormalRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
        } else ...{
          PaymentMethodSelector(
            uploadMethod: state.uploadMethod,
            costEstimateAr: state.costEstimateAr,
            costEstimateTurbo: state.costEstimateTurbo,
            hasNoTurboBalance: state.hasNoTurboBalance,
            isTurboUploadPossible: state.isTurboUploadPossible,
            arBalance: state.arBalance,
            sufficientArBalance: state.sufficientArBalance,
            turboCredits: state.turboCredits,
            sufficentCreditsBalance: state.sufficentCreditsBalance,
            isFreeThanksToTurbo: state.isFreeThanksToTurbo,
            onArSelect: () {
              context.read<HideBloc>().add(
                    const SelectUploadMethodEvent(
                      uploadMethod: UploadMethod.ar,
                    ),
                  );
            },
            onTurboSelect: () {
              context.read<HideBloc>().add(
                    const SelectUploadMethodEvent(
                      uploadMethod: UploadMethod.turbo,
                    ),
                  );
            },
            onTurboTopupSucess: () {
              context.read<HideBloc>().add(
                    const RefreshTurboBalanceEvent(),
                  );
            },
          )
        }
      ],
    );
  }

  Widget _buildPreparingAndSigningContent(BuildContext context) {
    return const Column(
      children: [
        Center(
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }

  Widget _buildUploadingContent(BuildContext context) {
    return const Column(
      children: [
        Center(
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }
}

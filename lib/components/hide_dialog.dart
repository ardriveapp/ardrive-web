import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToHide(
  BuildContext context, {
  required DriveDetailCubit driveDetailCubit,
}) async {
  return showAnimatedDialog(
    context,
    barrierDismissible: false,
    content: HideDialog(driveDetailCubit: driveDetailCubit),
  );
}

class HideDialog extends StatelessWidget {
  final DriveDetailCubit _driveDetailCubit;

  const HideDialog({
    super.key,
    required DriveDetailCubit driveDetailCubit,
  }) : _driveDetailCubit = driveDetailCubit;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HideBloc, HideState>(
      listener: (context, state) {
        if (state is SuccessHideState) {
          Navigator.of(context).pop();
          logger.d('Successfully hid/unhid entity');
        } else if (state is ConfirmingHideState) {
          _driveDetailCubit.refreshDriveDataTable();
          context.read<HideBloc>().add(const ConfirmUploadEvent());
        }
      },
      builder: (context, state) {
        return ArDriveStandardModal(
          title: _buildTitle(state.hideAction),
          content: _buildContent(),
          actions: _buildActions(context, state),
        );
      },
    );
  }

  String _buildTitle(HideAction hideAction) {
    switch (hideAction) {
      case HideAction.hideFile:
        return 'Hiding file'; // TODO: localize
      case HideAction.hideFolder:
        return 'Hiding folder'; // TODO: localize
      case HideAction.unhideFile:
        return 'Unhiding file'; // TODO: localize
      case HideAction.unhideFolder:
        return 'Unhiding folder'; // TODO: localize
    }
  }

  Widget _buildContent() {
    return const Column(
      children: [
        Center(
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }

  List<ModalAction>? _buildActions(
    BuildContext context,
    HideState state,
  ) {
    if (state is FailureHideState) {
      return [
        ModalAction(
          action: () {
            Navigator.of(context).pop();
          },
          title: appLocalizationsOf(context).cancel,
        ),
      ];
    } else {
      return null;
    }
  }
}

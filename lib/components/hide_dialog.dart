import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToHide(
  BuildContext context,
) async {
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
        } else if (state is ConfirmingHideState) {
          context.read<HideBloc>().add(const ConfirmUploadEvent());
        }
      },
      builder: (context, state) {
        return ArDriveStandardModal(
          title: _buildTitle(context, state),
          content: _buildContent(context, state),
        );
      },
    );
  }

  String _buildTitle(
    BuildContext context,
    HideState state,
  ) {
    final hideAction = state.hideAction;
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

  Widget _buildContent(
    BuildContext context,
    HideState state,
  ) {
    return const Column(
      children: [
        Center(
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }
}

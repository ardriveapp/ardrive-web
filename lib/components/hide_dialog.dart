import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToToggleHideState(
  BuildContext context, {
  required ArDriveDataTableItem item,
}) async {
  final hideBloc = context.read<HideBloc>();
  final driveDetailCubit = context.read<DriveDetailCubit>();

  final isHidden = item.isHidden;

  if (item is FileDataTableItem) {
    if (isHidden) {
      hideBloc.add(UnhideFileEvent(
        driveId: item.driveId,
        fileId: item.id,
      ));
    } else {
      hideBloc.add(HideFileEvent(
        driveId: item.driveId,
        fileId: item.id,
      ));
    }
  } else if (item is FolderDataTableItem) {
    if (isHidden) {
      hideBloc.add(UnhideFolderEvent(
        driveId: item.driveId,
        folderId: item.id,
      ));
    } else {
      hideBloc.add(HideFolderEvent(
        driveId: item.driveId,
        folderId: item.id,
      ));
    }
  } else if (item is DriveDataItem) {
    if (isHidden) {
      hideBloc.add(UnhideDriveEvent(
        driveId: item.driveId,
      ));
    } else {
      hideBloc.add(HideDriveEvent(
        driveId: item.driveId,
      ));
    }
  } else {
    throw UnimplementedError('Unknown item type: ${item.runtimeType}');
  }

  return showAnimatedDialog(
    context,
    barrierDismissible: false,
    content: HideDialog(driveDetailCubit: driveDetailCubit),
  );
}

Future<void> hideMultipleItems(
  BuildContext context, {
  required DriveID driveId,
  required List<FileDataTableItem> items,
}) async {
  final hideBloc = context.read<HideBloc>();
  final driveDetailCubit = context.read<DriveDetailCubit>();
  hideBloc.add(HideMultipleFilesEvent(
    driveId: driveId,
    fileIds: items.map((e) => e.id).toList(),
  ));

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
          _driveDetailCubit.refreshDriveDataTable();
          context.read<GlobalHideBloc>().add(RefreshOptions(
                userHasHiddenItems:
                    context.read<GlobalHideBloc>().state.userHasHiddenDrive,
              ));
        } else if (state is ConfirmingHideState) {
          _driveDetailCubit.refreshDriveDataTable();
          context.read<HideBloc>().add(const ConfirmUploadEvent());
        }
      },
      builder: (context, state) {
        return ArDriveStandardModalNew(
          title: _buildTitle(context, state),
          content: _buildContent(context, state),
          actions: _buildActions(context, state),
        );
      },
    );
  }

  String _buildTitle(BuildContext context, HideState state) {
    final hideAction = state.hideAction;
    if (state is FailureHideState) {
      switch (hideAction) {
        case HideAction.hideFile:
          return appLocalizationsOf(context).failedToHideFile;
        case HideAction.hideFolder:
          return appLocalizationsOf(context).failedToHideFolder;
        case HideAction.unhideFile:
          return appLocalizationsOf(context).failedToUnhideFile;
        case HideAction.unhideFolder:
          return appLocalizationsOf(context).failedToUnhideFolder;
        case HideAction.hideDrive:
          return 'Failed to hide drive';
        case HideAction.unhideDrive:
          return 'Failed to unhide drive';
      }
    }

    switch (hideAction) {
      case HideAction.hideFile:
        return appLocalizationsOf(context).hidingFile;
      case HideAction.hideFolder:
        return appLocalizationsOf(context).hidingFolder;
      case HideAction.unhideFile:
        return appLocalizationsOf(context).unhidingFile;
      case HideAction.unhideFolder:
        return appLocalizationsOf(context).unhidingFolder;
      case HideAction.hideDrive:
        return 'Hiding drive';
      case HideAction.unhideDrive:
        return 'Unhiding drive';
    }
  }

  Widget _buildContent(BuildContext context, HideState state) {
    if (state is FailureHideState) {
      final hideAction = state.hideAction;

      switch (hideAction) {
        case HideAction.hideFile:
          return Text(appLocalizationsOf(context).failedToHideFile);
        case HideAction.hideFolder:
          return Text(appLocalizationsOf(context).failedToHideFolder);
        case HideAction.unhideFile:
          return Text(appLocalizationsOf(context).failedToUnhideFile);
        case HideAction.unhideFolder:
          return Text(appLocalizationsOf(context).failedToUnhideFolder);
        case HideAction.hideDrive:
          return const Text('Failed to hide drive');
        case HideAction.unhideDrive:
          return const Text('Failed to unhide drive');
      }
    }

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
          title: appLocalizationsOf(context).close,
        ),
      ];
    } else {
      return null;
    }
  }
}

import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/components/turbo_credits_funding.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToToggleHideState(
  BuildContext context, {
  required ArDriveDataTableItem item,
}) async {
  final hideBloc = context.read<HideBloc>();
  final driveDetailCubit = context.read<DriveDetailCubit>();
  // The hidden file's row leaves the list before the hide reports success,
  // and [context] (its menu's) goes with it, so the name offer below is
  // shown from the navigator's, which stays.
  final navigator = Navigator.of(context, rootNavigator: true);

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

  await showArDriveDialog(
    context,
    barrierDismissible: false,
    content: HideDialog(driveDetailCubit: driveDetailCubit),
  );

  // A named file just left public view: offer to remove its name too.
  if (item is FileDataTableItem &&
      !isHidden &&
      item.isOwner &&
      hideBloc.state is SuccessHideState &&
      navigator.mounted) {
    await offerToRemoveArNSNameAfterHide(
      navigator.context,
      item: ArNSNameableItem(
        fileId: item.id,
        driveId: item.driveId,
        name: item.name,
        dataTxId: item.dataTxId,
        isManifest: item.contentType == ContentType.manifest,
      ),
    );
  }
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
        } else if (state is ConfirmingHideState && state.isInstant) {
          // Free: written straight away, as hiding always has been. Anything
          // else waits on the review below.
          _driveDetailCubit.refreshDriveDataTable();
          context.read<HideBloc>().add(const ConfirmUploadEvent());
        }
      },
      builder: (context, state) {
        if (state is ConfirmingHideState && !state.isInstant) {
          return _review(context, state);
        }
        return ArDriveStandardModalNew(
          title: _buildTitle(context, state),
          content: _buildContent(context, state),
          actions: _buildActions(context, state),
        );
      },
    );
  }

  /// Not free: what the change costs, and Add credits when credits are
  /// short, the same review as a license.
  Widget _review(BuildContext context, ConfirmingHideState state) {
    final l10n = appLocalizationsOf(context);
    final bloc = context.read<HideBloc>();
    final entry = state.hideEntitySettings.entry;
    final name = switch (entry) {
      FileEntry(:final name) => name,
      FolderEntry(:final name) => name,
      Drive(:final name) => name,
      _ => '',
    };
    final hiding = switch (state.hideAction) {
      HideAction.hideFile ||
      HideAction.hideFolder ||
      HideAction.hideDrive =>
        true,
      _ => false,
    };
    return UploadReviewDialog(
      title: switch (state.hideAction) {
        HideAction.hideFile => l10n.reviewHideFile,
        HideAction.hideFolder => l10n.reviewHideFolder,
        HideAction.hideDrive => l10n.reviewHideDrive,
        HideAction.unhideFile => l10n.reviewUnhideFile,
        HideAction.unhideFolder => l10n.reviewUnhideFolder,
        HideAction.unhideDrive => l10n.reviewUnhideDrive,
      },
      destination: name,
      files: const [],
      summary: state.summary,
      primaryLabel: hiding ? l10n.hide : l10n.unhide,
      subject: ReviewCostSubject.change,
      onUpload: (_) => bloc.add(const ConfirmUploadEvent()),
      onCancel: () => Navigator.of(context).pop(),
      funding: TurboCreditsFunding(
        context,
        onRefresh: () => bloc.add(const HideCostRefreshEvent()),
      ),
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
          child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
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

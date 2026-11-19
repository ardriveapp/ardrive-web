import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/folder_picker_body.dart';
import 'package:ardrive/components/payment_required_notice.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToMove(
  BuildContext parentContext, {
  required String driveId,
  required List<ArDriveDataTableItem> selectedItems,
}) {
  return showArDriveDialog(
    parentContext,
    barrierDismissible: false,
    content: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => FsEntryMoveBloc(
            crypto: ArDriveCrypto(),
            driveId: driveId,
            selectedItems: selectedItems,
            arweave: context.read<ArweaveService>(),
            turboUploadService: context.read<TurboUploadService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            syncCubit: context.read<SyncCubit>(),
          )..add(const FsEntryMoveInitial()),
        ),
        BlocProvider.value(
          value: parentContext.read<DriveDetailCubit>(),
        )
      ],
      child: const FsEntryMoveForm(),
    ),
  );
}

class FsEntryMoveForm extends StatefulWidget {
  const FsEntryMoveForm({super.key});

  @override
  State<FsEntryMoveForm> createState() => _FsEntryMoveFormState();
}

class _FsEntryMoveFormState extends State<FsEntryMoveForm> {
  /// The step the dialog was last on (the folder list, or the name conflict),
  /// kept while the move runs or fails so the dialog stays as it was and says
  /// the rest in itself.
  FsEntryMoveState? _step;

  /// Making a folder in the folder in view, in place of the list.
  bool _creatingFolder = false;

  /// Set when a move is asked for, cleared when the bloc answers with a
  /// failure or a conflict: the bloc checks the wallet and the names before it
  /// reports it is busy, so a quick second press would otherwise move twice.
  bool _inFlight = false;

  /// A move that is turned back before anything is reported (Wander could not
  /// be reached and the person chose Cancel) emits no state at all, so the
  /// flag is released after a while unless the bloc has gone busy.
  void _releaseIfStuck(BuildContext context) {
    final bloc = context.read<FsEntryMoveBloc>();
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && bloc.state is! FsEntryMoveLoadInProgress) {
        setState(() => _inFlight = false);
      }
    });
  }

  /// Every item is already in the folder in view, so moving there would
  /// change nothing.
  bool _alreadyHere(FsEntryMoveLoadSuccess state) {
    final here = state.viewingFolder.folder.id;
    return state.itemsToMove.isNotEmpty &&
        state.itemsToMove.every((item) => switch (item) {
              FileDataTableItem(:final parentFolderId) =>
                parentFolderId == here,
              FolderDataTableItem(:final parentFolderId) =>
                parentFolderId == here,
              _ => false,
            });
  }

  void _moveHere(BuildContext context, FsEntryMoveLoadSuccess state) {
    if (_inFlight) return;
    setState(() => _inFlight = true);
    _releaseIfStuck(context);
    context.read<FsEntryMoveBloc>().add(
          FsEntryMoveSubmit(
            folderInView: state.viewingFolder.folder,
            showHiddenItems:
                context.read<GlobalHideBloc>().state is ShowingHiddenItems,
          ),
        );
    context.read<DriveDetailCubit>().forceDisableMultiselect = true;
  }

  void _skipConflicts(BuildContext context, FsEntryMoveNameConflict state) {
    if (_inFlight) return;
    setState(() => _inFlight = true);
    _releaseIfStuck(context);
    context.read<FsEntryMoveBloc>().add(
          FsEntryMoveSkipConflicts(
            folderInView: state.folderInView,
            conflictingItems: state.conflictingItems,
            showHiddenItems:
                context.read<GlobalHideBloc>().state is ShowingHiddenItems,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FsEntryMoveBloc, FsEntryMoveState>(
      listener: (context, state) {
        if (state is FsEntryMoveSuccess) {
          Navigator.pop(context);
        } else if (state is FsEntryMoveWalletMismatch) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        if (state is FsEntryMoveLoadSuccess ||
            state is FsEntryMoveNameConflict) {
          _step = state;
        }
        final step = _step;
        if (state is FsEntryMoveFailure ||
            state is FsEntryMoveNameConflict ||
            state is FsEntryMoveWalletMismatch) {
          _inFlight = false;
        }
        final busy =
            step != null && (_inFlight || state is FsEntryMoveLoadInProgress);
        final failure = state is FsEntryMoveFailure ? state : null;
        final l10n = appLocalizationsOf(context);

        Widget? notice(VoidCallback retry) {
          if (failure == null) return null;
          return failure.isPaymentError
              ? const PaymentRequiredNotice()
              : ArDriveNotice(
                  type: ArDriveNoticeType.error,
                  title: l10n.couldNotMoveTitle,
                  message: l10n.actionFailedTryAgain,
                  actionLabel: l10n.tryAgain,
                  onAction: retry,
                );
        }

        if (step is FsEntryMoveNameConflict) {
          final names =
              step.conflictingFileNames() + step.conflictingFolderNames();
          final typography = ArDriveTypographyNew.of(context);
          final failureNotice = notice(() => _skipConflicts(context, step));
          return ArDriveStandardModalNew(
            title: l10n.nameConflict,
            scrollableContent: true,
            content: SizedBox(
              width: kMediumDialogWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.itemMoveNameConflict(step.destinationName),
                    style: typography.paragraphNormal(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colorTokens
                          .textMid,
                    ),
                  ),
                  const SizedBox(height: ArDriveSpacing.sm),
                  for (final name in names)
                    Padding(
                      padding: const EdgeInsets.only(bottom: ArDriveSpacing.xs),
                      child: Text(name, style: typography.paragraphNormal()),
                    ),
                  if (failureNotice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: ArDriveSpacing.md),
                      child: failureNotice,
                    ),
                ],
              ),
            ),
            actions: [
              ModalAction.close(
                action: () => Navigator.pop(context),
                title: l10n.cancelEmphasized,
                isEnable: !busy,
              ),
              if (!step.areAllItemsConflicting())
                ModalAction(
                  action: () => _skipConflicts(context, step),
                  title: l10n.skipAndMoveRest,
                  isLoading: busy,
                ),
            ],
          );
        }

        if (step is! FsEntryMoveLoadSuccess) {
          return const SizedBox();
        }

        if (_creatingFolder) {
          return folderCreateStep(
            context,
            driveId: step.viewingFolder.folder.driveId,
            parentFolderId: step.viewingFolder.folder.id,
            onClose: () {
              setState(() => _creatingFolder = false);
              // A failed move left the list unwatched; watch it again so the
              // new folder shows.
              context.read<FsEntryMoveBloc>().add(
                    FsEntryMoveUpdateTargetFolder(
                      folderId: step.viewingFolder.folder.id,
                    ),
                  );
            },
          );
        }

        final globalHideBloc = context.read<GlobalHideBloc>();
        final subFolders = globalHideBloc.state is ShowingHiddenItems
            ? step.viewingFolder.subfolders
            : step.viewingFolder.subfolders.where((f) => !f.isHidden).toList();
        final failureNotice = notice(() => _moveHere(context, step));

        return ArDriveStandardModalNew(
          width: folderPickerWidth(context),
          scrollableContent: true,
          title: l10n.moveItems,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (failureNotice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: ArDriveSpacing.md),
                  child: failureNotice,
                ),
              FolderPickerBody(
                folders: subFolders,
                fileNames: step.viewingFolder.files.map((f) => f.name).toList(),
                atRoot: step.viewingRootFolder,
                enabled: !busy,
                isFolderEnabled: (f) =>
                    step.itemsToMove.where((item) => item.id == f.id).isEmpty,
                onOpenFolder: (id) => context.read<FsEntryMoveBloc>().add(
                      FsEntryMoveUpdateTargetFolder(folderId: id),
                    ),
                onBack: () => context.read<FsEntryMoveBloc>().add(
                      FsEntryMoveGoBackToParent(
                        folderInView: step.viewingFolder.folder,
                      ),
                    ),
                onCreateFolder: () => setState(() => _creatingFolder = true),
              ),
            ],
          ),
          actions: [
            ModalAction.close(
              action: () => Navigator.pop(context),
              title: l10n.cancelEmphasized,
              isEnable: !busy,
            ),
            ModalAction(
              action: () => _moveHere(context, step),
              title: l10n.moveHereEmphasized,
              isLoading: busy,
              isEnable: !_alreadyHere(step),
            ),
          ],
        );
      },
    );
  }
}

import 'package:ardrive/components/reactive_select_field.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/components/upload_options.dart';
import 'package:ardrive/components/upload_review_cost.dart';
import 'package:ardrive/components/turbo_credits_funding.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/components/file_share_dialog.dart';
import 'package:ardrive/components/drive_share_dialog.dart';
import 'dart:async';
import 'dart:math';

import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/blocs/upload/enums/conflicting_files_actions.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/payment_method/view/upload_payment_method_view.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/blocs/upload/upload_progress_summary.dart';
import 'package:ardrive/blocs/upload/upload_handles/file_v2_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/components/help_info_modals.dart';
import 'package:ardrive/components/license/cc_type_form.dart';
import 'package:ardrive/components/license/udl_params_form.dart';
import 'package:ardrive/components/license/view_license_definition.dart';
import 'package:ardrive/components/license_details_popover.dart';
import 'package:ardrive/components/private_drive_marks.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/core/arfs/utils/arfs_revision_status_utils.dart';
import 'package:ardrive/core/upload/domain/repository/upload_repository.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/core/upload/view/blocs/upload_manifest_options_bloc.dart';
import 'package:ardrive/core/upload/view/manifest_options/manifest_options.dart';
import 'package:ardrive/entities/manifest_data.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/manifest/domain/manifest_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:pst/pst.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../blocs/upload/upload_handles/bundle_upload_handle.dart';
import '../pages/drive_detail/components/drive_explorer_item_tile.dart';

/// Picks files for [parentFolderId] and opens the upload dialog for them.
///
/// [drive] is the drive [driveId] names. Left out, it is the one the
/// explorer's [DriveDetailCubit] has open; a page with no drive open (Names,
/// Web pages) hands it in.
Future<void> promptToUpload(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
  required bool isFolderUpload,
  Drive? drive,
  List<IOFile>? files,
  bool autoReplaceConflicts = false,
}) async {
  final driveDetailCubit = context.read<DriveDetailCubit>();
  final manifestRepository = ManifestRepositoryImpl(
    context.read<DriveDao>(),
    ArDriveUploader(
      turboUploadUri: Uri.parse(configService.config.defaultTurboUploadUrl!),
      getArweaveForD2n: () => context.read<ArweaveService>().client,
      metadataGenerator: ARFSUploadMetadataGenerator(
        tagsGenerator: ARFSTagsGenerator(
          appInfoServices: AppInfoServices(),
        ),
      ),
      pstService: context.read<PstService>(),
    ),
    context.read<FolderRepository>(),
    ManifestDataBuilder(
      fileRepository: context.read<FileRepository>(),
      folderRepository: context.read<FolderRepository>(),
    ),
    ARFSRevisionStatusUtils(context.read<FileRepository>()),
    context.read<FileRepository>(),
  );
  final createManifestCubit = CreateManifestCubit(
    profileCubit: context.read<ProfileCubit>(),
    manifestRepository: manifestRepository,
    drive: drive ??
        (driveDetailCubit.state as DriveDetailLoadSuccess).currentDrive,
    auth: context.read<ArDriveAuth>(),
    folderRepository: context.read<FolderRepository>(),
  );

  final cubit = UploadCubit(
    activityTracker: context.read<ActivityTracker>(),
    arDriveUploadManager: context.read<ArDriveUploadPreparationManager>(),
    uploadFileSizeChecker: context.read<UploadFileSizeChecker>(),
    driveId: driveId,
    parentFolderId: parentFolderId,
    profileCubit: context.read<ProfileCubit>(),
    driveDao: context.read<DriveDao>(),
    uploadFolders: isFolderUpload,
    auth: context.read<ArDriveAuth>(),
    configService: context.read<ConfigService>(),
    uploadRepository: context.read<UploadRepository>(),
    manifestRepository: manifestRepository,
    createManifestCubit: createManifestCubit,
    autoReplaceConflicts: autoReplaceConflicts,
  );

  if (files != null) {
    _showUploadForm(context, cubit: cubit, driveDetailCubit: driveDetailCubit);
    cubit.selectFiles(files, parentFolderId);
    return;
  } else if (isFolderUpload) {
    cubit.pickFilesFromFolder(context: context, parentFolderId: parentFolderId);
  } else {
    cubit.pickFiles(context: context, parentFolderId: parentFolderId);
  }

  cubit.stream.listen((state) async {
    if (state is UploadLoadingFilesSuccess) {
      _showUploadForm(context,
          cubit: cubit, driveDetailCubit: driveDetailCubit);
    }
  });
}

Future<void> _showUploadForm(
  BuildContext context, {
  required UploadCubit cubit,
  required DriveDetailCubit driveDetailCubit,
}) async {
  final uploadCubit = BlocProvider<UploadCubit>(
    create: (context) => cubit,
  );

  final uploadPaymentMethodBloc = BlocProvider(
    create: (context) => UploadPaymentMethodBloc(
      context.read<ProfileCubit>(),
      context.read<ArDriveUploadPreparationManager>(),
      context.read<ArDriveAuth>(),
      context.read<PaymentService>(),
      CreditSharingService.fromConfig(context.read<ConfigService>()),
    ),
  );

  if (!context.mounted) {
    return;
  }
  await showArDriveDialog(
    context,
    content: MultiBlocProvider(
      providers: [
        uploadCubit,
        uploadPaymentMethodBloc,
      ],
      child: UploadForm(
        driveDetailCubit: driveDetailCubit,
      ),
    ),
    barrierDismissible: false,
    // The review fills a phone less a 16 margin.
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
  );
}

class UploadForm extends StatefulWidget {
  const UploadForm({super.key, required this.driveDetailCubit});

  final DriveDetailCubit driveDetailCubit;

  @override
  State<UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends State<UploadForm> {
  bool _isShowingCancelDialog = false;

  /// The name step for one public file (docs/NAMES.md): null while names
  /// are off or for any other upload.
  ArNSFlowNameCubit? _names;
  bool _namesStarted = false;

  ArNSFlowNameCubit? _nameStep(UploadReady state) {
    if (_namesStarted) return _names;
    if (!state.uploadIsPublic || state.numberOfFiles != 1) return null;
    _namesStarted = true;
    final names = _names = createArNSFlowNameCubit(context);
    // A new version of a named file: its names move with it.
    final existing = state.params.conflictingFiles.values.firstOrNull;
    if (names != null && existing != null) {
      context
          .read<DriveDao>()
          .fileById(fileId: existing)
          .getSingleOrNull()
          .then((file) {
        if (!mounted || file == null) return;
        names.setFollowing(arnsNamesOnVersion(context, file.dataTxId));
      });
    }
    return names;
  }

  /// Runs the name step once the file exists, after the upload dialog has
  /// closed, and says how it went. The upload stands either way.
  void _applyNames(BuildContext navigatorContext, UploadComplete state) {
    final names = _names;
    _names = null;
    if (names == null) return;
    if (!names.hasWork || state.dataTxIds.length != 1) {
      names.close();
      return;
    }
    final outcome = names.applyTo(state.dataTxIds.single);
    showArDriveDialog(
      navigatorContext,
      barrierDismissible: false,
      content: FutureBuilder<ArNSFlowOutcome>(
        future: outcome.whenComplete(names.close),
        builder: (context, result) {
          final strings = appLocalizationsOf(context);
          if (!result.hasData) {
            return ArDriveStandardModalNew(
              title: strings.arnsSettingTheName,
              content: const ArDriveLinearProgress(),
            );
          }
          return ArDriveStandardModalNew(
            title: result.data!.failed.isEmpty
                ? strings.arnsNameSaved
                : strings.arnsChangeNotMade,
            content: ArNSFlowNameResult(outcome: result.data!),
            actions: [
              ModalAction(
                title: strings.doneEmphasized,
                action: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Says the files are saved, with a way to share them, once the dialog has
  /// closed.
  void _showSaved(BuildContext navigatorContext, UploadComplete state) {
    final messenger = ScaffoldMessenger.maybeOf(navigatorContext);
    final reviewed = context.read<UploadCubit>().lastReadyState;
    final count = state.numberOfFiles;
    if (messenger == null || count == 0) return;
    final drive = reviewed?.params.targetDrive;
    final folder = reviewed?.params.targetFolder;

    VoidCallback? share;
    if (drive != null && folder != null) {
      switch (uploadSavedShare(
        fileCount: count,
        fileIds: state.fileIds,
        inDriveRoot: folder.id == drive.rootFolderId,
        drivePublic: drive.isPublic,
      )) {
        case UploadSavedShare.file:
          share = () => promptToShareFile(
                context: navigatorContext,
                driveId: drive.id,
                fileId: state.fileIds.single,
              );
        case UploadSavedShare.folder:
          share = () => promptToShareDrive(
                context: navigatorContext,
                drive: drive,
                folderId: folder.id,
                folderName: folder.name,
              );
        case UploadSavedShare.drive:
          share = () => promptToShareDrive(
                context: navigatorContext,
                drive: drive,
              );
        case UploadSavedShare.none:
          share = null;
      }
    }

    showUploadSavedToast(
      messenger,
      text: appLocalizationsOf(context).filesSavedForGood(count),
      shareLabel: appLocalizationsOf(context).share,
      onShare: share,
    );
  }

  @override
  void dispose() {
    _names?.close();
    super.dispose();
  }

  @override
  initState() {
    super.initState();

    context.read<UploadCubit>().startUploadPreparation();
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<UploadPaymentMethodBloc, UploadPaymentMethodState>(
        listener: (context, state) {
          if (state is UploadPaymentMethodLoaded) {
            context.read<UploadCubit>().setUploadMethod(
                  state.paymentMethodInfo.uploadMethod,
                  state.paymentMethodInfo,
                  state.canUpload,
                );
          } else if (state is UploadPaymentMethodError) {
            context.read<UploadCubit>().emitErrorFromPreparation();
          }
        },
        child: BlocConsumer<UploadCubit, UploadState>(
          listener: (context, state) {
            if (state is EmptyUpload) {
              Navigator.pop(context);
            }

            if (state is UploadComplete || state is UploadWalletMismatch) {
              if (!_isShowingCancelDialog) {
                final navigatorContext = Navigator.of(context).context;
                Navigator.pop(context);
                if (state is UploadComplete) {
                  _showSaved(navigatorContext, state);
                  _applyNames(navigatorContext, state);
                }
                context.read<ActivityTracker>().setUploading(false);

                // The file is already in the local database, so nothing needs
                // syncing for it to be *seen*. What it does need is
                // confirming: this asks again every few minutes until the
                // transaction is mined, and then stops.
                //
                // The comment that used to sit here said a background periodic
                // sync would take care of it. It would not: that timer is
                // gated on `autoSync`, which ships false in all three
                // flavours, so an uploaded file stayed unconfirmed until the
                // reader pressed sync or logged in again.
                context.read<SyncCubit>().watchForPendingConfirmations();
              }

              widget.driveDetailCubit.refreshDriveDataTable();
            }
            if (state is UploadWalletMismatch) {
              Navigator.pop(context);
              context.read<ProfileCubit>().logoutProfile();
            } else if (state is UploadReadyToPrepare) {
              context
                  .read<UploadPaymentMethodBloc>()
                  .add(PrepareUploadPaymentMethod(params: state.params));
            }
          },
          buildWhen: (previous, current) =>
              (current is! UploadComplete && current is! UploadReadyToPrepare),
          builder: (context, state) {
            if (state is UploadFolderNameConflict) {
              return _UploadFolderNameConflictWidget(state: state);
            } else if (state is UploadLoadingFiles) {
              return const _UploadLoadingFilesWidget();
            } else if (state is UploadLoadingFilesSuccess) {
              return const _UploadLoadingFilesSuccessWidget();
            } else if (state is UploadConflictWithFailedFiles) {
              return _UploadConflictWithFailedFilesWidget(state: state);
            } else if (state is UploadFileConflict) {
              return _UploadFileConflictWidget(state: state);
            } else if (state is UploadFileTooLarge) {
              return _UploadFileTooLargeWidget(state: state);
            } else if (state is UploadPreparationInProgress ||
                state is UploadPreparationInitialized) {
              return _PreparingUploadWidget(state: state);
            } else if (state is UploadReady) {
              return BlocProvider(
                create: (context) {
                  List<ManifestSelection> manifestSelections = [];
                  List<String> selectedManifestIds = [];

                  manifestSelections = state.manifestFiles.map((e) {
                    final selectedManifest = state.selectedManifestSelections
                        .firstWhereOrNull((selectedManifest) =>
                            selectedManifest.manifest.id == e.entry.id);

                    if (selectedManifest != null) {
                      selectedManifestIds.add(e.entry.id);
                    }

                    return ManifestSelection(manifest: e.entry);
                  }).toList();

                  return UploadManifestOptionsBloc(
                    manifestFiles: manifestSelections,
                    selectedManifestIds: selectedManifestIds,
                  );
                },
                child: BlocListener<UploadManifestOptionsBloc,
                    UploadManifestOptionsState>(
                  listener: (context, state) {
                    if (state is UploadManifestOptionsReady) {
                      context.read<UploadCubit>().updateManifestSelection(
                            state.manifestFiles
                                .where((e) => state.selectedManifestIds
                                    .contains(e.manifest.id))
                                .toList(),
                          );
                    }
                  },
                  child: _UploadReadyWidget(
                    state: state,
                    driveDetailCubit: widget.driveDetailCubit,
                    names: _nameStep(state),
                  ),
                ),
              );
            } else if (state is UploadConfiguringLicense) {
              return _UploadConfiguringLicenseWidget(state: state);
            } else if (state is UploadReview) {
              return _UploadReviewWidget(state: state);
            } else if (state is UploadSigningInProgress) {
              return _UploadSigningInProgressWidget(state: state);
            } else if (state is UploadInProgress) {
              return _UploadInProgressWidget(
                state: state,
                onChangeCancelWarning: (value) {
                  _isShowingCancelDialog = value;
                },
              );
            } else if (state is UploadCanceled) {
              return const _UploadCanceledWidget();
            } else if (state is UploadFailure) {
              return _UploadFailureWidget(state: state);
            } else if (state is UploadShowingWarning) {
              // TODO: Fix use of startUpload
              return _UploadShowingWarningWidget(state: state);
            } else if (state is UploadingManifests) {
              return _UploadingManifestsWidget(state: state);
            } else if (state is UploadManifestSelectPaymentMethod) {
              return _SelectPaymentMethodManifestUpload(state: state);
            } else if (state is UploadReviewWithLicense) {
              return _UploadReviewWithLicenseWidget(state: state);
            }
            return const Center(
              child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
            );
          },
        ),
      );
}

class _UploadingManifestsWidget extends StatelessWidget {
  const _UploadingManifestsWidget({required this.state});

  final UploadingManifests state;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).uploadingDeployments,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: ListView.builder(
                itemCount: state.manifestFiles.length,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ArDriveIcons.manifest(size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${state.manifestFiles[index].entry.name}...',
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                            ),
                          ),
                          const Spacer(),
                          if (state.manifestFiles[index].isUploading) ...[
                            const SizedBox(width: 8),
                            const ArDriveSpinner(),
                          ],
                          if (state.manifestFiles[index].isCompleted) ...[
                            const SizedBox(width: 8),
                            ArDriveIcons.checkCirle(size: 16),
                          ],
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            Text(
              'Uploaded ${state.completedCount} of ${state.manifestFiles.length} deployments',
              style: typography.paragraphNormal(),
            ),
          ],
        ),
      ),
      actions: [
        ModalAction.dismiss(
          action: () {
            context.read<UploadCubit>().cancelManifestsUpload();
          },
          title: appLocalizationsOf(context).cancel,
        ),
      ],
    );
  }
}

class StatsScreen extends StatefulWidget {
  final UploadReady readyState;
  final List<ArDriveButtonNew> modalActions;
  final List<Widget> children;

  final bool hasCloseButton;

  /// See [UploadReadyModalBase.showAdvancedLink].
  final bool showAdvancedLink;

  const StatsScreen({
    super.key,
    required this.readyState,
    this.hasCloseButton = true,
    this.showAdvancedLink = true,
    required this.modalActions,
    required this.children,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _scrollController = ScrollController();

  List<UploadHandle>? files;

  @override
  void initState() {
    logger.d(
      ' is button to upload enabled: ${widget.readyState.isNextButtonEnabled}',
    );

    final v2Files = widget
        .readyState.paymentInfo.uploadPlanForAR?.fileV2UploadHandles.values
        .map((e) => e)
        .toList();

    final bundles = widget
        .readyState.paymentInfo.uploadPlanForAR?.bundleUploadHandles
        .toList();

    if (v2Files != null) {
      files = [];

      files!.addAll(v2Files);
    }

    if (bundles != null) {
      files ??= [];

      files!.addAll(bundles);
    }

    PlausibleEventTracker.trackUploadReview(
      drivePrivacy: widget.readyState.uploadIsPublic
          ? DrivePrivacy.public
          : DrivePrivacy.private,
      dragNDrop: widget.readyState.isDragNDrop,
    );

    super.initState();
  }

  /// With more files than this, the list shows the first [_collapsedRows]
  /// and a "+ N more" line.
  static const _maxRowsShown = 5;
  static const _collapsedRows = 4;

  bool _showAllFiles = false;

  /// Every file being uploaded, taken out of its bundles.
  List<({String name, int size, String contentType})> get _rows => [
        for (final file in files!)
          if (file is FileV2UploadHandle)
            (
              name: file.entity.name!,
              size: file.size,
              contentType: file.entity.dataContentType ?? '',
            )
          else
            for (final entity in (file as BundleUploadHandle).fileEntities)
              (
                name: entity.name!,
                size: entity.size!,
                contentType: entity.dataContentType ?? '',
              ),
      ];

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);

    Widget row(({String name, int size, String contentType}) file) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              getIconForContentType(file.contentType, size: 16),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  file.name,
                  overflow: TextOverflow.ellipsis,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textMid,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                filesize(file.size),
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textLow,
                ),
              ),
            ],
          ),
        );

    final rows = files == null ? null : _rows;
    final collapsible = rows != null && rows.length > _maxRowsShown;
    final footerStyle = typography.paragraphSmall(
      fontWeight: ArFontWeight.semiBold,
      color: colorTokens.textLow,
    );

    return UploadReadyModalBase(
      readyState: widget.readyState,
      hasCloseButton: widget.hasCloseButton,
      showAdvancedLink: widget.showAdvancedLink,
      actions: widget.modalActions,
      children: [
        if (rows == null)
          // TODO: Replace progress indicator with error view
          const Center(child: ArDriveSpinner(size: ArDriveSpinnerSize.large))
        else if (collapsible && _showAllFiles)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 156),
            child: ArDriveScrollBar(
              controller: _scrollController,
              alwaysVisible: true,
              child: ListView.builder(
                padding: const EdgeInsets.only(right: 8),
                controller: _scrollController,
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, index) => row(rows[index]),
              ),
            ),
          )
        else
          ...(collapsible ? rows.take(_collapsedRows) : rows).map(row),
        // The total, and the way to the rest of a long list. One file's size
        // is already on its row.
        if (rows != null && rows.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                if (collapsible)
                  ArDriveClickArea(
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _showAllFiles = !_showAllFiles),
                      child: Text(
                        _showAllFiles
                            ? l10n.showFewerFiles
                            : l10n.moreFiles(rows.length - _collapsedRows),
                        style: footerStyle.copyWith(
                          color: colorTokens.textMid,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  l10n.totalUploadSize(filesize(widget.readyState.totalSize)),
                  style: footerStyle,
                ),
              ],
            ),
          ),
        const Divider(height: 32),
        ...widget.children,
      ],
    );
  }
}

class ConfiguringLicenseScreen extends StatelessWidget {
  final String headingText;
  final UploadReady readyState;
  final FormGroup formGroup;
  final Widget child;

  const ConfiguringLicenseScreen({
    super.key,
    required this.headingText,
    required this.readyState,
    required this.formGroup,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ReactiveForm(
      formGroup: formGroup,
      child: ReactiveFormConsumer(
        builder: (_, form, __) => UploadReadyModalBase(
          readyState: readyState,
          actions: getModalActions(context, readyState, form),
          children: [
            Text(
              headingText,
              style: ArDriveTypographyNew.of(context).paragraphLarge(
                color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
                fontWeight: ArFontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  List<ArDriveButtonNew> getModalActions(
      BuildContext context, UploadReady state, FormGroup form) {
    // The same width as the other upload screens' buttons. With no width
    // they stretched across the dialog.
    const customWidth = 100.0;
    final title = appLocalizationsOf(context).next;
    final typography = ArDriveTypographyNew.of(context);

    return [
      ArDriveButtonNew(
        onPressed: () => {
          context.read<UploadCubit>().configuringLicenseBack(),
        },
        text: appLocalizationsOf(context).back,
        variant: ButtonVariant.secondary,
        typography: typography,
        maxWidth: customWidth,
      ),
      ArDriveButtonNew(
        typography: typography,
        isDisabled: !form.valid,
        maxWidth: customWidth,
        onPressed: () {
          context.read<UploadCubit>().configuringLicenseNext();
        },
        variant: ButtonVariant.primary,
        text: title,
      ),
    ];
  }
}

class UploadReadyModalBase extends StatefulWidget {
  final UploadReady readyState;
  final List<ArDriveButtonNew> actions;
  final List<Widget> children;

  final bool hasCloseButton;
  final double width;

  /// Whether the header offers "Advanced" (updating manifests) when there are
  /// manifests to update. The first upload screen offers it in its Options
  /// instead.
  final bool showAdvancedLink;

  const UploadReadyModalBase({
    super.key,
    required this.readyState,
    required this.actions,
    required this.children,
    this.hasCloseButton = true,
    this.width = 440,
    this.showAdvancedLink = true,
  });

  @override
  State<UploadReadyModalBase> createState() => _UploadReadyModalBaseState();
}

class _UploadReadyModalBaseState extends State<UploadReadyModalBase> {
  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(modalBorderRadius),
      child: ArDriveScrollBar(
        child: SingleChildScrollView(
          child: BlocBuilder<UploadCubit, UploadState>(
            builder: (context, state) {
              final settingsOpen = state is UploadReady && state.showSettings;
              return ScreenTypeLayout.builder(
                desktop: (context) => ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 185,
                    // Fits its content, up to most of the window: a fixed
                    // 580 pushed the warnings under the payment choice out
                    // of sight once there were a few files.
                    maxHeight:
                        max(580, MediaQuery.of(context).size.height * 0.85),
                    maxWidth: (state is UploadReady) && (state.showSettings)
                        ? widget.width * 2
                        : widget.width,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorTokens.containerRed,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(modalBorderRadius),
                              topRight: Radius.circular(modalBorderRadius),
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: Row(
                          // With the manifest panel open, the panel sets the
                          // height and this column fills it, buttons at the
                          // bottom, rather than floating in the middle.
                          crossAxisAlignment: settingsOpen
                              ? CrossAxisAlignment.stretch
                              : CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              flex: 1,
                              child: Container(
                                color: colorTokens.containerL2,
                                padding: const EdgeInsets.only(
                                    left: 32.0, top: 32, right: 32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          appLocalizationsOf(context)
                                              .uploadNFiles(widget
                                                  .readyState.numberOfFiles),
                                          style: typography.heading5(
                                            fontWeight: ArFontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (state is UploadReady &&
                                            !state.showSettings &&
                                            widget.readyState.canShowSettings &&
                                            widget.showAdvancedLink)
                                          GestureDetector(
                                            onTap: () {
                                              context
                                                  .read<UploadCubit>()
                                                  .showSettings();
                                            },
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Transform.translate(
                                                  offset: const Offset(0, -1),
                                                  child: Text(
                                                    'Advanced',
                                                    style: typography
                                                        .paragraphSmall(
                                                            fontWeight:
                                                                ArFontWeight
                                                                    .semiBold),
                                                  ),
                                                ),
                                                ArDriveIcons.advancedChevron(
                                                  size: 18,
                                                ),
                                              ],
                                            ),
                                          ),
                                        if ((state is UploadReady) &&
                                            (state.showSettings) &&
                                            widget.readyState.canShowSettings)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 8.0),
                                            child: GestureDetector(
                                              onTap: () {
                                                context
                                                    .read<UploadCubit>()
                                                    .hideSettings();
                                              },
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Transform.translate(
                                                    offset: const Offset(0, -1),
                                                    child: Text(
                                                      'Close',
                                                      style: typography
                                                          .paragraphSmall(
                                                              fontWeight:
                                                                  ArFontWeight
                                                                      .semiBold),
                                                    ),
                                                  ),
                                                  Transform.rotate(
                                                    angle: 180 * pi / 180,
                                                    child: ArDriveIcons
                                                        .advancedChevron(
                                                            size: 18),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                      ],
                                    ),
                                    EncryptedUploadNote(
                                      isPrivate:
                                          !widget.readyState.uploadIsPublic,
                                    ),
                                    const SizedBox(height: 20),
                                    // Content taller than the dialog can
                                    // grow scrolls, rather than running into
                                    // the buttons.
                                    Flexible(
                                      fit: settingsOpen
                                          ? FlexFit.tight
                                          : FlexFit.loose,
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: widget.children,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 24.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: widget.actions.map((action) {
                                          return Flexible(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4.0),
                                              child: action,
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ),
                            if (state is UploadReady && state.showSettings)
                              Flexible(
                                flex: 1,
                                child: Container(
                                  color: colorTokens.containerL3,
                                  padding: const EdgeInsets.only(
                                      left: 32.0, top: 32, right: 32),
                                  height: double.maxFinite,
                                  width: double.maxFinite,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        appLocalizationsOf(context)
                                            .updateDeployments,
                                        style: typography.heading5(
                                          fontWeight: ArFontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Flexible(
                                        child: BlocBuilder<UploadCubit,
                                            UploadState>(
                                          builder: (context, state) {
                                            if (state is UploadReady &&
                                                state.showSettings) {
                                              return ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxHeight:
                                                      MediaQuery.of(context)
                                                              .size
                                                              .height *
                                                          0.7,
                                                ),
                                                child: manifestOptionsView(
                                                    state, context, typography),
                                              );
                                            }
                                            return const SizedBox();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                mobile: (context) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 6,
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorTokens.containerRed,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(modalBorderRadius),
                                  topRight: Radius.circular(modalBorderRadius),
                                ),
                              ),
                            ),
                          ),
                          Column(
                            children: [
                              Container(
                                color: colorTokens.containerL2,
                                padding: const EdgeInsets.only(
                                    left: 32.0, top: 32, right: 32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          appLocalizationsOf(context)
                                              .uploadNFiles(widget
                                                  .readyState.numberOfFiles),
                                          style: typography.heading5(
                                            fontWeight: ArFontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    EncryptedUploadNote(
                                      isPrivate:
                                          !widget.readyState.uploadIsPublic,
                                    ),
                                    const SizedBox(height: 20),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: widget.children,
                                    ),
                                    const SizedBox(height: 20),
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 24.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: widget.actions.map((action) {
                                          return Flexible(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4.0),
                                              child: action,
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                              // TODO: add back
                              // if (state is UploadReady && state.showSettings)
                              //   Expanded(
                              //     child: Container(
                              //       color: colorTokens.containerL3,
                              //       width: double.maxFinite,
                              //       padding: const EdgeInsets.only(
                              //           left: 32.0, top: 32, right: 32),
                              //       child: Column(
                              //         mainAxisSize: MainAxisSize.min,
                              //         crossAxisAlignment:
                              //             CrossAxisAlignment.start,
                              //         children: [
                              //           Text(
                              //             'Update Manifest(s)',
                              //             style: typography.heading5(
                              //               fontWeight: ArFontWeight.bold,
                              //             ),
                              //           ),
                              //           const SizedBox(height: 20),
                              //           Expanded(
                              //             child: BlocBuilder<UploadCubit,
                              //                 UploadState>(
                              //               builder: (context, state) {
                              //                 if (state is UploadReady &&
                              //                     state.showSettings) {
                              //                   return manifestOptionsView(
                              //                       state, context, typography,
                              //                       scrollable: false);
                              //                 }
                              //                 return const SizedBox();
                              //               },
                              //             ),
                              //           ),
                              //         ],
                              //       ),
                              //     ),
                              //   ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget manifestOptionsView(
      UploadReady state, BuildContext context, ArdriveTypographyNew typography,
      {bool scrollable = true}) {
    return ManifestOptions(
      scrollable: scrollable,
    );
  }
}

class LicenseReviewInfo extends StatelessWidget {
  final LicenseState licenseState;

  const LicenseReviewInfo({
    super.key,
    required this.licenseState,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocalizationsOf(context).licenseHeading,
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textLow,
          ),
        ),
        Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: licenseState.params?.hasParams == true
                  ? LicenseNameWithPopoverButton(
                      licenseState: licenseState,
                      anchor: const Aligned(
                        follower: Alignment.bottomLeft,
                        target: Alignment.topLeft,
                      ),
                    )
                  : Text(
                      licenseState.meta.nameWithShortName,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
            ),
            if (licenseState.meta.licenseType != LicenseType.unknown)
              Text.rich(
                TextSpan(
                  children: [
                    const WidgetSpan(
                      child: SizedBox(width: 16),
                    ),
                    viewLicenseDefinitionTextSpan(
                      context,
                      licenseState.meta.licenseDefinitionTxId,
                    ),
                  ],
                ),
              )
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class LicenseNameWithPopoverButton extends StatefulWidget {
  final LicenseState licenseState;
  final Aligned anchor;

  const LicenseNameWithPopoverButton({
    super.key,
    required this.licenseState,
    required this.anchor,
  });

  @override
  State<LicenseNameWithPopoverButton> createState() =>
      _LicenseNameWithPopoverButtonState();
}

class _LicenseNameWithPopoverButtonState
    extends State<LicenseNameWithPopoverButton> {
  bool _showLicenseDetailsCard = false;

  @override
  Widget build(BuildContext context) {
    return ArDriveOverlay(
      onVisibleChange: (visible) {
        if (!visible) {
          setState(() {
            _showLicenseDetailsCard = false;
          });
        }
      },
      visible: _showLicenseDetailsCard,
      anchor: widget.anchor,
      content: LicenseDetailsPopover(
        licenseState: widget.licenseState,
        closePopover: () {
          setState(() {
            _showLicenseDetailsCard = false;
          });
        },
        showLicenseName: false,
      ),
      child: HoverWidget(
        hoverScale: 1.0,
        tooltip: appLocalizationsOf(context).showLicenseConfiguration,
        child: Text.rich(
          TextSpan(
            text: widget.licenseState.meta.nameWithShortName,
            style: ArDriveTypographyNew.of(context)
                .paragraphLarge(
                    color:
                        ArDriveTheme.of(context).themeData.colorTokens.textHigh)
                .copyWith(decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                setState(() {
                  _showLicenseDetailsCard = !_showLicenseDetailsCard;
                });
              },
          ),
        ),
      ),
    );
  }
}

class UploadReadyModal extends StatefulWidget {
  const UploadReadyModal({super.key});

  @override
  State<UploadReadyModal> createState() => _UploadReadyModalState();
}

class _UploadReadyModalState extends State<UploadReadyModal> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UploadCubit, UploadState>(
      builder: (context, state) {
        final typography = ArDriveTypographyNew.of(context);
        if (state is UploadReady) {
          return ReactiveForm(
            formGroup: context.watch<UploadCubit>().licenseCategoryForm,
            child: ReactiveFormConsumer(
              builder: (_, form, __) {
                final LicenseCategory? licenseCategory =
                    form.control('licenseCategory').value;
                return Flexible(
                  flex: 1,
                  child: StatsScreen(
                    readyState: state,
                    // Don't show on first screen?
                    hasCloseButton: false,
                    modalActions: [
                      ArDriveButtonNew(
                        onPressed: () => Navigator.of(context).pop(false),
                        text: appLocalizationsOf(context).cancel,
                        typography: typography,
                        maxWidth: 100,
                        variant: ButtonVariant.secondary,
                      ),
                      ...getModalActions(context, state, licenseCategory),
                    ],
                    children: [
                      RepositoryProvider.value(
                        value: context.read<ArDriveUploadPreparationManager>(),
                        child: BlocProvider(
                          create: (context) => UploadPaymentMethodBloc(
                            context.read<ProfileCubit>(),
                            context.read<ArDriveUploadPreparationManager>(),
                            context.read<ArDriveAuth>(),
                            context.read<PaymentService>(),
                            CreditSharingService.fromConfig(
                                context.read<ConfigService>()),
                          )..add(PrepareUploadPaymentMethod(
                              params: state.params,
                            )),
                          child: UploadPaymentMethodView(
                            onError: () {
                              context
                                  .read<UploadCubit>()
                                  .emitErrorFromPreparation();
                            },
                            onTurboTopupSucess: () {
                              context
                                  .read<UploadCubit>()
                                  .startUploadPreparation(
                                    isRetryingToPayWithTurbo: true,
                                  );
                            },
                            onUploadMethodChanged: (method, info, canUpload) {
                              context
                                  .read<UploadCubit>()
                                  .setUploadMethod(method, info, canUpload);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        } else {
          return const SizedBox();
        }
      },
    );
  }
}

class _SelectPaymentMethodManifestUpload extends StatefulWidget {
  const _SelectPaymentMethodManifestUpload({required this.state});

  final UploadManifestSelectPaymentMethod state;

  @override
  State<_SelectPaymentMethodManifestUpload> createState() =>
      _SelectPaymentMethodManifestUploadState();
}

class _SelectPaymentMethodManifestUploadState
    extends State<_SelectPaymentMethodManifestUpload> {
  bool _buttonEnabled = false;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocProvider(
      create: (context) => UploadPaymentMethodBloc(
        context.read<ProfileCubit>(),
        context.read<ArDriveUploadPreparationManager>(),
        context.read<ArDriveAuth>(),
        context.read<PaymentService>(),
        CreditSharingService.fromConfig(context.read<ConfigService>()),
      )..add(
          PrepareUploadPaymentMethod(
            params: UploadParams(
              conflictingFiles: {},
              files: widget.state.files,
              foldersByPath:
                  UploadPlanUtils.generateFoldersForFiles(widget.state.files),
              targetDrive: widget.state.drive,
              targetFolder: widget.state.parentFolder,
              user: context.read<ArDriveAuth>().currentUser,
              // Theres no thumbnail generation for manifests
              containsSupportedImageTypeForThumbnailGeneration: false,
            ),
          ),
        ),
      child: BlocListener<UploadPaymentMethodBloc, UploadPaymentMethodState>(
        listener: (context, state) {
          if (state is UploadPaymentMethodLoaded) {
            setState(() {
              _buttonEnabled = state.canUpload;
            });
          }
        },
        child: ArDriveStandardModalNew(
          title: appLocalizationsOf(context).uploadSettings,
          width: kMediumDialogWidth,
          content: Column(
            children: [
              Text(
                appLocalizationsOf(context).deploymentsOverFreeLimit,
                style: typography.paragraphNormal(color: colorTokens.textMid),
              ),
              const SizedBox(height: 16),
              UploadPaymentMethodView(
                onUploadMethodChanged: (method, methodInfo, canUpload) {
                  context
                      .read<UploadCubit>()
                      .setManifestUploadMethod(method, methodInfo, canUpload);
                },
                onError: () {},
                loadingIndicator: Center(
                  child: Column(
                    children: [
                      Text(
                        appLocalizationsOf(context).loadingPaymentMethods,
                        style: typography.paragraphLarge(
                          color: colorTokens.textHigh,
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: 8.0, horizontal: 32),
                        child: ArDriveLinearProgress(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            ModalAction(
              action: () {
                context.read<UploadCubit>().cancelManifestsUpload();
              },
              title: appLocalizationsOf(context).cancel,
            ),
            ModalAction(
              isEnable: _buttonEnabled,
              action: () {
                context
                    .read<UploadCubit>()
                    .uploadManifests(widget.state.manifestModels);
              },
              title: appLocalizationsOf(context).upload,
            ),
          ],
        ),
      ),
    );
  }
}

/// The upload's percentage ring. Drawn here rather than with ArDriveSpinner:
/// a 40px ring in the brand red with the percentage inside is its own
/// indicator, not a loading spinner.
class CircularProgressWidget extends StatelessWidget {
  final double progress; // progress value from 0 to 100

  const CircularProgressWidget({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 4,
            valueColor: AlwaysStoppedAnimation<Color>(colorTokens.strokeRed),
            backgroundColor: colorTokens.strokeMid,
          ),
        ),
        Center(
          child: Text(
            '${(progress * 100).toInt()}%',
            style: typography.paragraphSmall(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadFolderNameConflictWidget extends StatelessWidget {
  final UploadFolderNameConflict state;
  const _UploadFolderNameConflictWidget({required this.state});

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).duplicateFolders(
        state.conflictingFileNames.length,
      ),
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizationsOf(context).foldersWithTheSameNameAlreadyExists(
                state.conflictingFileNames.length,
              ),
              style: ArDriveTypographyNew.of(context).paragraphNormal(
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.textMid),
            ),
            const SizedBox(height: ArDriveSpacing.md),
            _ConflictingFilesList(
              names: state.conflictingFileNames,
              areFolders: true,
            ),
          ],
        ),
      ),
      // Cancel first, so that Skip, the way on, is the primary button.
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).cancel,
        ),
        if (!state.areAllFilesConflicting)
          ModalAction(
            action: () => context.read<UploadCubit>().checkConflictingFiles(),
            title: appLocalizationsOf(context).skip,
          ),
      ],
    );
  }
}

class _UploadConflictWithFailedFilesWidget extends StatelessWidget {
  final UploadConflictWithFailedFiles state;
  const _UploadConflictWithFailedFilesWidget({required this.state});

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).retryFailedUploadsTitle,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizationsOf(context).retryFailedUploadsDescription(
                state.conflictingFileNamesForFailedFiles.length,
              ),
              style: ArDriveTypographyNew.of(context).paragraphNormal(
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.textMid),
            ),
            const SizedBox(height: ArDriveSpacing.md),
            _ConflictingFilesList(
              names: state.conflictingFileNamesForFailedFiles,
            ),
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () => context
              .read<UploadCubit>()
              .checkConflictingFiles(checkFailedFiles: false),
          title: appLocalizationsOf(context).skip,
        ),
        ModalAction(
          action: () => context
              .read<UploadCubit>()
              .prepareUploadPlanAndCostEstimates(
                  uploadAction: UploadActions.skipSuccessfulUploads),
          title: appLocalizationsOf(context).replaceFailedUploads,
        ),
      ],
    );
  }
}

/// The names an upload clashes with, under their label: one row per name with
/// its type's icon, scrolling past a dozen or so. The three conflict dialogs
/// each drew this their own way.
class _ConflictingFilesList extends StatelessWidget {
  const _ConflictingFilesList({required this.names, this.areFolders = false});

  final List<String> names;
  final bool areFolders;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appLocalizationsOf(context).conflictingFiles,
          style: typography.paragraphNormal(
            color: colorTokens.textHigh,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
        const SizedBox(height: ArDriveSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: names.length,
            itemBuilder: (context, index) => SizedBox(
              height: 32,
              child: Row(
                children: [
                  getIconForContentType(
                    areFolders
                        ? 'folder'
                        : getFileExtensionFromFileName(fileName: names[index]),
                    size: 16,
                  ),
                  const SizedBox(width: ArDriveSpacing.xs),
                  Expanded(
                    child: Text(
                      names[index],
                      overflow: TextOverflow.ellipsis,
                      style: typography.paragraphNormal(
                        color: colorTokens.textHigh,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadFileConflictWidget extends StatelessWidget {
  final UploadFileConflict state;
  const _UploadFileConflictWidget({required this.state});

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveStandardModalNew(
      // Wide enough for its content and for Cancel, Skip and Upload as new
      // version on one row; narrower, the third button wraps to a second row.
      width: kMediumDialogWidth + 144,
      title: appLocalizationsOf(context)
          .duplicateFiles(state.conflictingFileNames.length),
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizationsOf(context).filesWithTheSameNameAlreadyExists(
                state.conflictingFileNames.length,
              ),
              style: typography.paragraphNormal(color: colorTokens.textMid),
            ),
            const SizedBox(height: ArDriveSpacing.md),
            _ConflictingFilesList(names: state.conflictingFileNames),
          ],
        ),
      ),
      // Cancel first and the main action last, as in the other upload
      // dialogs: the last button is the primary one.
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).cancel,
        ),
        if (!state.areAllFilesConflicting)
          ModalAction(
            action: () => context
                .read<UploadCubit>()
                .prepareUploadPlanAndCostEstimates(
                    uploadAction: UploadActions.skip),
            title: appLocalizationsOf(context).skip,
          ),
        ModalAction(
          action: () => context
              .read<UploadCubit>()
              .prepareUploadPlanAndCostEstimates(
                  uploadAction: UploadActions.replace),
          title: appLocalizationsOf(context)
              .uploadAsNewVersion(state.conflictingFileNames.length),
        ),
      ],
    );
  }
}

class _UploadFileTooLargeWidget extends StatelessWidget {
  final UploadFileTooLarge state;
  const _UploadFileTooLargeWidget({required this.state});

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context)
          .filesTooLarge(state.tooLargeFileNames.length),
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kIsWeb
                  ? (state.isPrivate
                      ? appLocalizationsOf(context)
                          .filesTooLargeExplanationPrivate
                      : appLocalizationsOf(context)
                          .filesTooLargeExplanationPublic)
                  : appLocalizationsOf(context).filesTooLargeExplanationMobile,
              style: ArDriveTypographyNew.of(context).paragraphNormal(
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.textMid),
            ),
            const SizedBox(height: ArDriveSpacing.md),
            Text(
              appLocalizationsOf(context).tooLargeForUpload,
              style: ArDriveTypographyNew.of(context).paragraphNormal(
                color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            Text(
              state.tooLargeFileNames.join(', '),
              style: ArDriveTypographyNew.of(context).paragraphNormal(
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.textHigh),
            ),
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).cancel,
        ),
        if (state.hasFilesToUpload)
          ModalAction(
            action: () => context
                .read<UploadCubit>()
                .skipLargeFilesAndCheckForConflicts(),
            title: appLocalizationsOf(context).skip,
          ),
      ],
    );
  }
}

class _PreparingUploadWidget extends StatelessWidget {
  const _PreparingUploadWidget({required this.state});
  final UploadState state;

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).preparingUpload,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ArDriveSpinner(size: ArDriveSpinnerSize.large),
            const SizedBox(height: ArDriveSpacing.md),
            Text(
              state is UploadPreparationInProgress &&
                      (state as UploadPreparationInProgress).isArConnect
                  ? appLocalizationsOf(context).arConnectRemainOnThisTab
                  : appLocalizationsOf(context).thisMayTakeAWhile,
              style: ArDriveTypographyNew.of(context).paragraphNormal(
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.textMid),
              textAlign: TextAlign.center,
            )
          ],
        ),
      ),
    );
  }
}

class _UploadReadyWidget extends StatelessWidget {
  const _UploadReadyWidget({
    required this.state,
    required this.driveDetailCubit,
    this.names,
  });

  final UploadReady state;
  final DriveDetailCubit driveDetailCubit;
  final ArNSFlowNameCubit? names;

  @override
  Widget build(BuildContext context) {
    final names = this.names;
    if (names == null) return _build(context);
    // The upload button waits for the name step: priced, wallet ready.
    return BlocBuilder<ArNSNameDialogCubit, ArNSNameDialogState>(
      bloc: names,
      builder: (context, _) => BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
        builder: (context, __) => _build(context),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);
    final paymentBloc = context.watch<UploadPaymentMethodBloc>();
    final info = state.paymentInfo;
    // Read again after Add credits or Try again: no price until it is back.
    final summary = paymentBloc.state is UploadPaymentMethodLoading
        ? null
        : UploadReviewSummary.fromPaymentInfo(info);
    final folderName = state.params.targetFolder.name;

    return ReactiveForm(
      formGroup: context.watch<UploadCubit>().licenseCategoryForm,
      child: ReactiveFormConsumer(
        builder: (_, form, __) {
          final LicenseCategory? licenseCategory =
              form.control('licenseCategory').value;
          final cubit = context.read<UploadCubit>();

          // A license is set up, and manifests chosen, on steps of their own
          // before the upload starts; the button goes to the first of them.
          final label = licenseCategory != null
              ? l10n.configure
              : state.selectedManifestSelections.isNotEmpty
                  ? l10n.review
                  : l10n.upload;

          return UploadReviewDialog(
            title: l10n.uploadNFiles(state.numberOfFiles),
            destination: state.uploadIsPublic
                ? l10n.uploadReviewToPublic(folderName)
                : l10n.uploadReviewToPrivate(folderName),
            files: uploadReviewFiles(info),
            summary: summary,
            primaryLabel: label,
            primaryEnabled: state.isNextButtonEnabled && (names?.ready ?? true),
            // The way the review showed is the way it is paid, whatever the
            // payment sheet defaulted to.
            onUpload: (method) => cubit.uploadFromReview(
              method: method,
              licenseCategory: licenseCategory,
            ),
            onShown: () => PlausibleEventTracker.trackUploadReview(
              drivePrivacy: state.uploadIsPublic
                  ? DrivePrivacy.public
                  : DrivePrivacy.private,
              dragNDrop: state.isDragNDrop,
            ),
            onCancel: () => Navigator.of(context).pop(false),
            funding: TurboCreditsFunding(
              context,
              onRefresh: () => paymentBloc
                  .add(PrepareUploadPaymentMethod(params: state.params)),
            ),
            paymentChoice: RepositoryProvider.value(
              value: context.read<ArDriveUploadPreparationManager>(),
              child: UploadPaymentMethodView(
                // The review says what is short, above the choice; only the
                // wallet-only case keeps the selector's own messages.
                showBalanceMessages: summary?.usesLegacySelector ?? false,
                walletOnlyWhenChosen: !(summary?.usesLegacySelector ?? false),
                onError: cubit.emitErrorFromPreparation,
                onTurboTopupSucess: () => cubit.startUploadPreparation(
                    isRetryingToPayWithTurbo: true),
                onUploadMethodChanged: (method, info, canUpload) =>
                    cubit.setUploadMethod(method, info, canUpload),
              ),
            ),
            sourceWalletNotice: info.sourceWalletCredits == null
                ? null
                : SourceWalletCreditsNotice(
                    credits: info.sourceWalletCredits!,
                    onShare: paymentBloc.canShareSourceWalletCredits
                        ? paymentBloc.shareSourceWalletCredits
                        : null,
                  ),
            extras: [
              if (names != null) ArNSFlowNameSection(cubit: names!),
              // Everything else is optional, and most uploads leave it as it
              // is: one line saying what is set, opened on request.
              UploadOptions(
                key: const ValueKey('upload-options'),
                // This upload's own choice, not the default it started from:
                // coming back from the license screens must not undo it.
                thumbnails: state
                        .params.containsSupportedImageTypeForThumbnailGeneration
                    ? cubit.uploadThumbnail
                    : null,
                onThumbnailsChanged: cubit.changeUploadThumbnailOption,
                summary: [
                  if (licenseCategory == null)
                    l10n.noLicense
                  else
                    l10n.namedLicense(_licenseShortNames[licenseCategory] ??
                        licenseCategoryNames[licenseCategory]!),
                  if (state.shouldShowCustomManifestCheckbox &&
                      state.uploadFileAsCustomManifest)
                    l10n.uploadAsManifest,
                  if (state.selectedManifestSelections.isNotEmpty)
                    l10n.manifestsToUpdate(
                        state.selectedManifestSelections.length),
                ],
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.licenseHeading,
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ArDriveClickArea(
                        tooltip: l10n.learnMoreAboutLicenses,
                        child: GestureDetector(
                          onTap: () {
                            showLicensingInfoModal(context: context);
                          },
                          // The same mark as the thumbnails option beside it.
                          child: ArDriveIcons.info(
                            color: colorTokens.textMid,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: ArDriveSpacing.xs),
                    child: ReactiveForm(
                      formGroup: cubit.licenseCategoryForm,
                      child: ReactiveArDriveSelectField<LicenseCategory?>(
                        formControlName: 'licenseCategory',
                        showErrors: (control) =>
                            control.dirty && control.invalid,
                        validationMessages: kValidationMessages(l10n),
                        choices: [
                          for (final value in [null, ...LicenseCategory.values])
                            ArDriveChoice(
                              value: value,
                              label:
                                  licenseCategoryNames[value] ?? l10n.noLicense,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (state.shouldShowCustomManifestCheckbox)
                    ArDriveCheckBox(
                      title: l10n.publishManifestAsDeployment,
                      checked: state.uploadFileAsCustomManifest,
                      useNewIcons: true,
                      titleStyle: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                      ),
                      onChange: cubit.setIsUploadingCustomManifest,
                    ),
                  if (state.canShowSettings && !state.showSettings)
                    ArDriveLink(
                      text: l10n.updateManifests,
                      isAction: true,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colorTokens.textMid,
                      ),
                      onTap: cubit.showSettings,
                    ),
                ],
              ),
              // The deployments to update, in the review rather than a panel
              // beside it, so the review keeps one width.
              if (state.canShowSettings && state.showSettings)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.updateDeployments,
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                            ),
                          ),
                        ),
                        ArDriveLink(
                          text: l10n.close,
                          isAction: true,
                          style: typography.paragraphSmall(
                            fontWeight: ArFontWeight.semiBold,
                            color: colorTokens.textMid,
                          ),
                          onTap: cubit.hideSettings,
                        ),
                      ],
                    ),
                    const SizedBox(height: ArDriveSpacing.xs),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: const ManifestOptions(),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Short names for the Options summary; the dropdown keeps the full ones.
const _licenseShortNames = {
  LicenseCategory.udl: 'UDL',
  LicenseCategory.cc: 'CC',
};

class _UploadConfiguringLicenseWidget extends StatelessWidget {
  const _UploadConfiguringLicenseWidget({required this.state});

  final UploadConfiguringLicense state;

  @override
  Widget build(BuildContext context) {
    final headingText =
        'Configure ${licenseCategoryNames[state.licenseCategory]}';
    switch (state.licenseCategory) {
      case LicenseCategory.udl:
        final udlParamsForm = context.watch<UploadCubit>().licenseUdlParamsForm;
        return ConfiguringLicenseScreen(
          headingText: headingText,
          readyState: state.readyState,
          formGroup: udlParamsForm,
          child: UdlParamsForm(
            formGroup: udlParamsForm,
            onChangeLicenseFee: () {},
          ),
        );
      case LicenseCategory.cc:
        final ccTypeForm = context.watch<UploadCubit>().licenseCcTypeForm;
        return ConfiguringLicenseScreen(
          headingText: headingText,
          readyState: state.readyState,
          formGroup: ccTypeForm,
          child: CcTypeForm(formGroup: ccTypeForm),
        );
      default:
        return const Text('Unsupported license category');
    }
  }
}

class _UploadReviewWithLicenseWidget extends StatelessWidget {
  const _UploadReviewWithLicenseWidget({required this.state});

  final UploadReviewWithLicense state;

  @override
  Widget build(BuildContext context) {
    final readyState = state.readyState;
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    double heightForManifestSelections =
        (readyState.selectedManifestSelections.length * 30) + 50;

    if (heightForManifestSelections > 200) {
      heightForManifestSelections = 175;
    }

    heightForManifestSelections += 50;

    return StatsScreen(
      readyState: readyState,
      modalActions: [
        ArDriveButtonNew(
          onPressed: () => {
            context.read<UploadCubit>().reviewBack(),
          },
          text: appLocalizationsOf(context).back,
          typography: typography,
          maxWidth: 100,
          variant: ButtonVariant.secondary,
        ),
        ArDriveButtonNew(
          onPressed: () {
            context.read<UploadCubit>().reviewUpload();
          },
          text: uploadButtonLabel(context, state.readyState.numberOfFiles),
          typography: typography,
          maxWidth: ArDriveButtonNew.fittedWidth(
            context,
            uploadButtonLabel(context, state.readyState.numberOfFiles),
            minWidth: 100,
          ),
          variant: ButtonVariant.primary,
        ),
      ],
      children: [
        UploadReviewCost(paymentInfo: state.readyState.paymentInfo),
        LicenseReviewInfo(licenseState: state.licenseState),
        if (state.readyState.selectedManifestSelections.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: heightForManifestSelections,
                minWidth: kLargeDialogWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    appLocalizationsOf(context).updatedDeployments,
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textLow,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...state.readyState.selectedManifestSelections.map(
                          (e) => Column(
                            children: [
                              Row(
                                children: [
                                  ArDriveIcons.manifest(size: 16),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      e.manifest.name,
                                      style: typography.paragraphNormal(
                                        fontWeight: ArFontWeight.semiBold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UploadReviewWidget extends StatelessWidget {
  const _UploadReviewWidget({required this.state});

  final UploadReview state;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    double heightForManifestSelections =
        (state.readyState.selectedManifestSelections.length * 30) + 50;

    if (heightForManifestSelections > 200) {
      heightForManifestSelections = 200;
    }

    heightForManifestSelections += 50;

    return StatsScreen(
      readyState: state.readyState,
      modalActions: [
        ArDriveButtonNew(
          onPressed: () => {
            context.read<UploadCubit>().reviewBack(),
          },
          text: appLocalizationsOf(context).back,
          typography: typography,
          maxWidth: 100,
          variant: ButtonVariant.secondary,
        ),
        ArDriveButtonNew(
          onPressed: () {
            context.read<UploadCubit>().reviewUpload();
          },
          text: uploadButtonLabel(context, state.readyState.numberOfFiles),
          typography: typography,
          maxWidth: ArDriveButtonNew.fittedWidth(
            context,
            uploadButtonLabel(context, state.readyState.numberOfFiles),
            minWidth: 100,
          ),
          variant: ButtonVariant.primary,
        ),
      ],
      children: [
        UploadReviewCost(paymentInfo: state.readyState.paymentInfo),
        if (state.readyState.selectedManifestSelections.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: heightForManifestSelections,
                minWidth: kLargeDialogWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    appLocalizationsOf(context).updatedDeployments,
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textLow,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...state.readyState.selectedManifestSelections.map(
                          (e) => Column(
                            children: [
                              Row(
                                children: [
                                  ArDriveIcons.manifest(size: 16),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      e.manifest.name,
                                      style: typography.paragraphNormal(
                                        fontWeight: ArFontWeight.semiBold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UploadSigningInProgressWidget extends StatelessWidget {
  const _UploadSigningInProgressWidget({required this.state});
  final UploadSigningInProgress state;
  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: state.uploadPlan.bundleUploadHandles.isNotEmpty
          ? appLocalizationsOf(context).bundlingAndSigningUpload
          : appLocalizationsOf(context).signingUpload,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ArDriveSpinner(size: ArDriveSpinnerSize.large),
            const SizedBox(height: ArDriveSpacing.md),
            Text(
              state.isArConnect
                  ? appLocalizationsOf(context).arConnectRemainOnThisTab
                  : appLocalizationsOf(context).thisMayTakeAWhile,
              style: ArDriveTypographyNew.of(context).paragraphNormal(
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.textMid),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadFailureWidget extends StatelessWidget {
  const _UploadFailureWidget({required this.state});

  final UploadFailure state;

  @override
  Widget build(BuildContext context) {
    if (state.error == UploadErrors.turboTimeout) {
      return ArDriveStandardModalNew(
        title: appLocalizationsOf(context).uploadFailed,
        description: appLocalizationsOf(context).yourUploadFailedTurboTimeout,
        actions: [
          ModalAction(
            action: () => Navigator.of(context).pop(false),
            title: appLocalizationsOf(context).ok,
          ),
        ],
      );
    }

    final reviewed = context.read<UploadCubit>().lastReadyState;
    if (state.error == UploadErrors.turboPaymentRequired &&
        state.controller != null &&
        reviewed != null) {
      // Turbo refused it: the review again, with Add credits, and Upload
      // sends the files that were refused.
      return _UploadPaymentRequiredWidget(
        reviewed: reviewed,
        lastTryStillFinishing: state.lastTryStillFinishing,
      );
    }

    if (state.error == UploadErrors.turboPaymentRequired) {
      // Free allowance exhausted / insufficient credits: point the user at
      // the top-up flow instead of offering a re-upload that would 402 again.
      return ArDriveStandardModalNew(
        title: appLocalizationsOf(context).freeAllowanceUsedUpTitle,
        description: appLocalizationsOf(context).freeAllowanceUsedUpDescription,
        actions: [
          ModalAction(
            action: () => Navigator.of(context).pop(false),
            title: appLocalizationsOf(context).cancel,
          ),
          ModalAction(
            action: () {
              Navigator.of(context).pop(false);
              showTurboTopupModal(context);
            },
            title: appLocalizationsOf(context).buyCredits,
          ),
        ],
      );
    }

    // Paid from the wallet, these files' transactions may already be paid
    // for, and only this tab can finish them.
    final isWalletPaid =
        state.failedTasks?.any((t) => t.type == UploadType.d2n) ?? false;

    return ArDriveStandardModalNew(
      hasCloseButton: true,
      close: () => _close(context, isWalletPaid: isWalletPaid),
      width: state.failedTasks != null ? kLargeDialogWidth : kMediumDialogWidth,
      title: appLocalizationsOf(context).uploadProblemTitle,
      description: appLocalizationsOf(context).yourUploadFailed,
      content: state.failedTasks != null
          ? _failedUploadList(context, state.failedTasks!, isWalletPaid)
          : null,
      actions: state.failedTasks == null
          ? null
          : [
              ModalAction(
                action: () => _close(context, isWalletPaid: isWalletPaid),
                title: appLocalizationsOf(context).close,
              ),
              ModalAction(
                action: () {
                  context.read<UploadCubit>().retryUploads();
                },
                title: appLocalizationsOf(context).reUpload,
              ),
            ],
    );
  }

  /// Closes the dialog, after asking first when the files were paid from the
  /// wallet: closing leaves them unfinished, and they may be paid for.
  Future<void> _close(
    BuildContext context, {
    required bool isWalletPaid,
  }) async {
    if (!isWalletPaid) {
      Navigator.of(context).pop(false);
      return;
    }

    var leave = false;
    await showArDriveDialog(
      context,
      content: Builder(
        builder: (dialogContext) => ArDriveStandardModalNew(
          title: appLocalizationsOf(dialogContext).leaveFilesUnfinishedTitle,
          description:
              appLocalizationsOf(dialogContext).leaveFilesUnfinishedDescription,
          actions: [
            ModalAction(
              action: () {
                leave = true;
                Navigator.of(dialogContext).pop();
              },
              title: appLocalizationsOf(dialogContext).closeAnyway,
              customWidth: 140,
            ),
            ModalAction(
              action: () => Navigator.of(dialogContext).pop(),
              title: appLocalizationsOf(dialogContext).goBack,
            ),
          ],
        ),
      ),
    );

    if (leave && context.mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Widget _failedUploadList(
    BuildContext context,
    List<UploadTask> tasks,
    bool isWalletPaid,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
          maxHeight: 256 * 1.5, minWidth: kLargeDialogWidth),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                isWalletPaid
                    ? appLocalizationsOf(context).uploadFailedWalletFiles
                    : appLocalizationsOf(context).uploadFailedPartial,
                style: ArDriveTypographyNew.of(context).paragraphLarge(
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.textHigh,
                  fontWeight: ArFontWeight.bold,
                )),
            if (isWalletPaid) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ArDriveNotice(
                  type: ArDriveNoticeType.warning,
                  message:
                      appLocalizationsOf(context).uploadFailedWalletKeepTabOpen,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Sized to the files listed, up to the box's height, rather than
            // always filling it: one file left a large empty space.
            Flexible(
              child: ArDriveScrollBar(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  itemBuilder: (BuildContext context, int index) {
                    final task = tasks[index];

                    if (task.content != null) {
                      for (var file in task.content!) {
                        return ListTile(
                          leading: file is ARFSFileUploadMetadata
                              ? getIconForContentType(
                                  file.dataContentType,
                                  size: 16,
                                )
                              : file is ARFSFolderUploadMetatadata
                                  ? getIconForContentType(
                                      'folder',
                                      size: 16,
                                    )
                                  : null,
                          contentPadding: EdgeInsets.zero,
                          title: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                flex: 1,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file.name,
                                      style: ArDriveTypographyNew.of(context)
                                          .paragraphNormal(
                                        color: ArDriveTheme.of(context)
                                            .themeData
                                            .colorTokens
                                            .textHigh,
                                        fontWeight: ArFontWeight.semiBold,
                                      ),
                                    ),
                                    AnimatedSwitcher(
                                      duration: const Duration(seconds: 1),
                                      child: Column(
                                        children: [
                                          if (file is ARFSFileUploadMetadata)
                                            Text(
                                              filesize(file.size),
                                              style: ArDriveTypographyNew.of(
                                                      context)
                                                  .paragraphSmall(
                                                color: ArDriveTheme.of(context)
                                                    .themeData
                                                    .colorTokens
                                                    .textLow,
                                              ),
                                            ),
                                        ],
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
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadShowingWarningWidget extends StatelessWidget {
  const _UploadShowingWarningWidget({required this.state});

  final UploadShowingWarning state;

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).warning,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizationsOf(context).weDontRecommendUploadsAboveASafeLimit(
                filesize(fileSizeWarning),
              ),
              style: ArDriveTypographyNew.of(context).paragraphNormal(
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.textMid),
            ),
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).cancel,
        ),
        ModalAction(
          action: () {
            if (state.uploadPlanForAR != null) {
              return context.read<UploadCubit>().startUpload(
                    uploadPlanForAr: state.uploadPlanForAR!,
                    uploadPlanForTurbo: state.uploadPlanForTurbo,
                  );
            }

            return context.read<UploadCubit>().checkFilesAboveLimit();
          },
          title: appLocalizationsOf(context).uploadAnyway,
        ),
      ],
    );
  }
}

class _UploadCanceledWidget extends StatelessWidget {
  const _UploadCanceledWidget();

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).uploadCanceledTitle,
      description: appLocalizationsOf(context).uploadCanceledDescription,
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).ok,
        ),
      ],
    );
  }
}

class _UploadInProgressWidget extends StatelessWidget {
  const _UploadInProgressWidget({
    required this.state,
    required this.onChangeCancelWarning,
  });

  final UploadInProgress state;
  final Function(bool) onChangeCancelWarning;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress;
    final summary = UploadProgressSummary.from(progress);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return ArDriveStandardModalNew(
      actions: [
        if (state.progress.hasUploadInProgress)
          ModalAction(
            action: () {
              onChangeCancelWarning(true);
              final cubit = context.read<UploadCubit>();
              final paidWithCredits = state.uploadMethod == UploadMethod.turbo;

              showArDriveDialog(
                context,
                content: BlocBuilder<UploadCubit, UploadState>(
                  bloc: cubit,
                  builder: (context, state) {
                    if (state is UploadComplete) {
                      return ArDriveStandardModalNew(
                        title: appLocalizationsOf(context).uploadCompleteTitle,
                        description: appLocalizationsOf(context)
                            .uploadCompleteCannotCancel,
                        actions: [
                          ModalAction(
                            action: () {
                              // parent modal
                              Navigator.pop(context);

                              Navigator.pop(context);

                              onChangeCancelWarning(false);
                            },
                            title: appLocalizationsOf(context).ok,
                          ),
                        ],
                      );
                    }
                    return ArDriveStandardModalNew(
                      title: appLocalizationsOf(context).warning,
                      // What a cancel costs depends on how the upload is
                      // paid: credits for finished files are spent, while
                      // AR already sent from the wallet may still be charged.
                      description: paidWithCredits
                          ? appLocalizationsOf(context)
                              .cancelTurboUploadKeepsFinished
                          : appLocalizationsOf(context)
                              .cancelUploadMayStillCharge,
                      actions: [
                        ModalAction(
                          action: () {
                            onChangeCancelWarning(false);
                            Navigator.pop(context);
                          },
                          title: appLocalizationsOf(context).keepUploading,
                        ),
                        ModalAction(
                          action: () {
                            onChangeCancelWarning(false);
                            cubit.cancelUpload();
                            Navigator.pop(context);
                          },
                          title: appLocalizationsOf(context).cancelUpload,
                        ),
                      ],
                    );
                  },
                ),
              );
            },
            title: state.isCanceling
                ? appLocalizationsOf(context).cancelingUpload
                : appLocalizationsOf(context).cancel,
            // A lone action is primary by default, and Cancel is not the
            // main action here.
            variant: ButtonVariant.secondary,
          ),
      ],
      width: kLargeDialogWidth,
      title:
          '${appLocalizationsOf(context).uploadingNFiles(summary.numberOfFiles)} ${summary.percent}%',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kLargeDialogWidth,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 256 * 1.5),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Scrollbar(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: progress.tasks.length,
                    itemBuilder: (BuildContext context, int index) {
                      final task = progress.tasks.values.elementAt(index);

                      String? progressMessage;
                      String status = '';

                      switch (task.status) {
                        case UploadStatus.notStarted:
                          status = appLocalizationsOf(context)
                              .uploadStatusNotStarted;
                          break;
                        case UploadStatus.inProgress:
                          status = appLocalizationsOf(context)
                              .uploadStatusInProgress;
                          break;
                        case UploadStatus.paused:
                          status =
                              appLocalizationsOf(context).uploadStatusPaused;
                          break;
                        case UploadStatus.creatingMetadata:
                          status =
                              appLocalizationsOf(context).uploadStatusPreparing;
                          break;
                        case UploadStatus.encryting:
                          status = appLocalizationsOf(context)
                              .uploadStatusEncrypting;
                          break;
                        case UploadStatus.finalizing:
                          status = appLocalizationsOf(context)
                              .uploadStatusFinalizing;
                          break;
                        case UploadStatus.complete:
                          status =
                              appLocalizationsOf(context).uploadStatusComplete;
                          break;
                        case UploadStatus.failed:
                          status =
                              appLocalizationsOf(context).uploadStatusFailed;
                          break;
                        case UploadStatus.preparationDone:
                          status = appLocalizationsOf(context)
                              .uploadStatusPreparationDone;
                          break;
                        case UploadStatus.canceled:
                          status =
                              appLocalizationsOf(context).uploadStatusCanceled;
                          break;
                        case UploadStatus.creatingBundle:
                          status =
                              appLocalizationsOf(context).uploadStatusPreparing;
                        case UploadStatus.uploadingThumbnail:
                          status = appLocalizationsOf(context)
                              .uploadStatusUploadingThumbnail;
                          break;
                        case UploadStatus.assigningUndername:
                          if (task is FileUploadTask) {
                            status = appLocalizationsOf(context)
                                .uploadStatusAssigningArnsName(
                              task.metadata.assignedName ?? '',
                            );
                          }
                          break;
                      }

                      final statusAvailableForShowingProgress =
                          task.status == UploadStatus.failed ||
                              task.status == UploadStatus.inProgress ||
                              task.status == UploadStatus.complete ||
                              task.status == UploadStatus.finalizing;

                      if (!task.isProgressAvailable &&
                          task.status == UploadStatus.inProgress) {
                        progressMessage = appLocalizationsOf(context)
                            .uploadProgressNotAvailable;
                      }

                      // Each file at its own size, as on the confirm step. A
                      // folder has no size to show.
                      String? progressTextFor(ARFSUploadMetadata file) {
                        if (!task.isProgressAvailable) {
                          return progressMessage;
                        }

                        if (!statusAvailableForShowingProgress ||
                            task.uploadItem == null ||
                            file is! ARFSFileUploadMetadata) {
                          return null;
                        }

                        return '${filesize(UploadProgressSummary.uploadedBytes(file, task))}/${filesize(file.size)}';
                      }

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (task.content != null)
                            for (var file in task.content!)
                              ListTile(
                                leading: file is ARFSFileUploadMetadata
                                    ? getIconForContentType(
                                        file.dataContentType,
                                        size: 16,
                                      )
                                    : file is ARFSFolderUploadMetatadata
                                        ? getIconForContentType(
                                            'folder',
                                            size: 16,
                                          )
                                        : null,
                                contentPadding: EdgeInsets.zero,
                                title: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            file.name,
                                            style: typography.paragraphNormal(
                                              fontWeight: ArFontWeight.semiBold,
                                              color: colorTokens.textMid,
                                            ),
                                          ),
                                          AnimatedSwitcher(
                                            duration:
                                                const Duration(seconds: 1),
                                            child: Column(
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        status,
                                                        style: typography
                                                            .paragraphNormal(
                                                          fontWeight:
                                                              ArFontWeight
                                                                  .semiBold,
                                                          color: colorTokens
                                                              .textMid,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (progressTextFor(file) != null)
                                            Text(
                                              progressTextFor(file)!,
                                              style: typography.paragraphNormal(
                                                fontWeight:
                                                    ArFontWeight.semiBold,
                                                color: colorTokens.textLow,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.max,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          if (task.isProgressAvailable &&
                                              statusAvailableForShowingProgress) ...[
                                            CircularProgressWidget(
                                              progress: task.progress,
                                            ),
                                          ],
                                          if (!task.isProgressAvailable ||
                                              task.status ==
                                                  UploadStatus.creatingBundle ||
                                              task.status ==
                                                  UploadStatus.creatingMetadata)
                                            Flexible(
                                              flex: 2,
                                              child: SizedBox(
                                                child: LoadingAnimationWidget
                                                    .prograssiveDots(
                                                  color:
                                                      ArDriveTheme.of(context)
                                                          .themeData
                                                          .colorTokens
                                                          .textHigh,
                                                  size: 40,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          const Divider(height: 20)
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          // TODO: localize
          Text(
            'Total uploaded: ${filesize(summary.totalUploaded)} of ${filesize(summary.totalSize)}',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textMid,
            ),
          ),
          // TODO: localize
          Text(
            'Files uploaded: ${summary.numberOfUploadedFiles} of ${summary.numberOfFiles}',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textMid,
            ),
          ),
          // TODO: localize
          if (state.progress.hasUploadInProgress)
            Text(
              'Upload speed: ${filesize(state.progress.calculateUploadSpeed().toInt())}/s',
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textMid,
              ),
            ),
          if (state.uploadMethod == UploadMethod.ar) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ArDriveNotice(
                type: ArDriveNoticeType.warning,
                message:
                    appLocalizationsOf(context).uploadInProgressKeepTabOpen,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UploadLoadingFilesWidget extends StatelessWidget {
  const _UploadLoadingFilesWidget();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.delayed(const Duration(seconds: 1)),
      builder: (context, shapshot) {
        if (shapshot.connectionState == ConnectionState.done) {
          return const ArDriveStandardModalNew(
            title: 'Loading...',
            description:
                'Getting everything ready... We are fetching your selected files, checking for conflicts, and ensuring all is set for your upload. Please hold on...',
          );
        }
        return const SizedBox();
      },
    );
  }
}

class _UploadLoadingFilesSuccessWidget extends StatelessWidget {
  const _UploadLoadingFilesSuccessWidget();

  @override
  Widget build(BuildContext context) {
    return const ArDriveStandardModalNew(
      title: 'All set!',
      description: 'We are ready to start preparing your upload.',
    );
  }
}

List<ArDriveButtonNew> getModalActions(
  BuildContext context,
  UploadReady state,
  LicenseCategory? licenseCategory, {
  bool namesReady = true,
}) {
  final typography = ArDriveTypographyNew.of(context);
  final enabled = state.isNextButtonEnabled && namesReady;

  if (licenseCategory != null) {
    return [
      ArDriveButtonNew(
        isDisabled: !enabled,
        onPressed: () {
          context.read<UploadCubit>().initialScreenNext(
                licenseCategory: licenseCategory,
              );
        },
        text: appLocalizationsOf(context).configure,
        typography: typography,
        variant: ButtonVariant.primary,
        maxWidth: 140,
      ),
    ];
  } else if (state.selectedManifestSelections.isNotEmpty) {
    return [
      ArDriveButtonNew(
        isDisabled: !enabled,
        onPressed: () {
          context.read<UploadCubit>().initialScreenUpload();
        },
        text: appLocalizationsOf(context).review,
        typography: typography,
        maxWidth: 140,
        variant: ButtonVariant.primary,
      ),
    ];
  }

  return [
    ArDriveButtonNew(
      isDisabled: !enabled,
      onPressed: () {
        context.read<UploadCubit>().initialScreenUpload();
      },
      text: uploadButtonLabel(context, state.numberOfFiles),
      typography: typography,
      maxWidth: ArDriveButtonNew.fittedWidth(
        context,
        uploadButtonLabel(context, state.numberOfFiles),
        minWidth: 100,
      ),
      variant: ButtonVariant.primary,
    ),
  ];
}

/// The label of the button that starts an upload, such as "Upload 3 files".
String uploadButtonLabel(BuildContext context, int numberOfFiles) =>
    numberOfFiles > 0
        ? appLocalizationsOf(context).uploadNFiles(numberOfFiles)
        : appLocalizationsOf(context).upload;
//

/// Every file on [info]'s plan, taken out of its bundles, for the review.
List<UploadReviewFile> uploadReviewFiles(UploadPaymentMethodInfo info) {
  final plan = info.uploadPlanForAR;
  if (plan == null) return const [];
  return [
    for (final file in plan.fileV2UploadHandles.values)
      (
        name: file.entity.name!,
        size: file.size,
        contentType: file.entity.dataContentType ?? '',
      ),
    for (final bundle in plan.bundleUploadHandles)
      for (final entity in bundle.fileEntities)
        (
          name: entity.name!,
          size: entity.size!,
          contentType: entity.dataContentType ?? '',
        ),
  ];
}

/// After Turbo refused an upload as not paid for: the review again, with the
/// balance read fresh, Add credits, and Upload sending the refused files.
class _UploadPaymentRequiredWidget extends StatefulWidget {
  const _UploadPaymentRequiredWidget({
    required this.reviewed,
    this.lastTryStillFinishing = false,
  });

  final UploadReady reviewed;

  /// Upload was pressed while the refused try was still finishing, and
  /// nothing was sent.
  final bool lastTryStillFinishing;

  @override
  State<_UploadPaymentRequiredWidget> createState() =>
      _UploadPaymentRequiredWidgetState();
}

class _UploadPaymentRequiredWidgetState
    extends State<_UploadPaymentRequiredWidget> {
  /// Null while it is read.
  UploadReviewSummary? _summary;

  @override
  void initState() {
    super.initState();
    _read();
  }

  /// Reads the balance again, and Turbo's price too if it couldn't be read at
  /// review: reading only the balance, Try again could never clear "no price".
  Future<void> _read() async {
    setState(() => _summary = null);
    final payments = context.read<PaymentService>();
    final wallet = context.read<ArDriveAuth>().currentUser.wallet;
    final summary = await readRefusedUploadSummary(
      widget.reviewed.paymentInfo,
      readBalance: () => payments.getBalance(wallet: wallet),
      readPrice: (bytes) async {
        final winc = await payments.getPriceForBytes(byteSize: bytes);
        final perDollar = await payments.getPriceForFiat(
            wallet: null, amount: 100, currency: 'usd');
        return UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: winc,
          totalSize: bytes,
          usdUploadCost: winc / perDollar.winstonCredits,
        );
      },
    );
    if (mounted) setState(() => _summary = summary);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final reviewed = widget.reviewed;
    final folderName = reviewed.params.targetFolder.name;

    return UploadReviewDialog(
      title: l10n.uploadNFiles(reviewed.numberOfFiles),
      destination: reviewed.uploadIsPublic
          ? l10n.uploadReviewToPublic(folderName)
          : l10n.uploadReviewToPrivate(folderName),
      files: uploadReviewFiles(reviewed.paymentInfo),
      summary: _summary,
      primaryLabel: l10n.upload,
      onUpload: (_) => context.read<UploadCubit>().retryUploads(),
      extras: [
        if (widget.lastTryStillFinishing)
          SizedBox(
            width: double.infinity,
            child: ArDriveNotice(
              type: ArDriveNoticeType.info,
              message: l10n.uploadLastTryStillFinishing,
            ),
          ),
      ],
      onCancel: () => Navigator.of(context).pop(false),
      funding: TurboCreditsFunding(context, onRefresh: _read),
    );
  }
}

/// The note after an upload: how many files are saved, and Share.
void showUploadSavedToast(
  ScaffoldMessengerState messenger, {
  required String text,
  required String shareLabel,
  VoidCallback? onShare,
}) {
  showArDriveToast(
    messenger,
    text: text,
    type: ArDriveStatusType.success,
    duration: const Duration(seconds: 10),
    actionLabel: shareLabel,
    onAction: onShare,
  );
}

/// What Share offers after an upload.
enum UploadSavedShare { file, folder, drive, none }

/// One file shares the file. Several files share where they went only in a
/// public drive: the folder, or the drive from its root. In a private drive
/// both of those shares carry the drive's key, which opens everything in it,
/// far more than the files just saved, so several files offer no Share there.
///
/// [fileCount] is how many files the upload covered, the number the note
/// says. [fileIds] can be fewer: after a retry, only the files it sent again.
/// So one file shares the file only when the upload was one file.
UploadSavedShare uploadSavedShare({
  required int fileCount,
  required List<String> fileIds,
  required bool inDriveRoot,
  required bool drivePublic,
}) {
  if (fileCount == 1) {
    return fileIds.length == 1 ? UploadSavedShare.file : UploadSavedShare.none;
  }
  if (!drivePublic) return UploadSavedShare.none;
  return inDriveRoot ? UploadSavedShare.drive : UploadSavedShare.folder;
}

/// The review after Turbo refused an upload, read again: the balance, and
/// Turbo's price for its [UploadPaymentMethodInfo.totalSize] bytes when the
/// price at review was the zero placeholder for one that couldn't be read.
Future<UploadReviewSummary> readRefusedUploadSummary(
  UploadPaymentMethodInfo reviewed, {
  required Future<BigInt> Function() readBalance,
  required Future<UploadCostEstimate> Function(int byteCount) readPrice,
}) async {
  BigInt? balance;
  var balanceUnreadable = false;
  try {
    balance = await readBalance();
  } on TurboUserNotFound {
    balance = BigInt.zero;
  } catch (e) {
    logger.d('Could not read the balance after Turbo refused payment: $e');
    balanceUnreadable = true;
  }

  var info = reviewed;
  final price = reviewed.costEstimateTurbo?.totalCost ?? BigInt.zero;
  if (price <= BigInt.zero && reviewed.totalSize > 0) {
    try {
      info = reviewed.copyWith(
          costEstimateTurbo: await readPrice(reviewed.totalSize));
    } catch (e) {
      // Still no price: the summary says so, with Try again.
      logger.d('Could not read the price after Turbo refused payment: $e');
    }
  }

  return UploadReviewSummary.afterRefusal(
    info,
    creditsBalance: balance,
    balanceUnreadable: balanceUnreadable,
  );
}

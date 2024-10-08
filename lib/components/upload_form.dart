// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/arns/presentation/assign_name_modal.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/blocs/upload/enums/conflicting_files_actions.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/payment_method/view/upload_payment_method_view.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/blocs/upload/upload_handles/file_v2_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/components/license/cc_type_form.dart';
import 'package:ardrive/components/license/udl_params_form.dart';
import 'package:ardrive/components/license/view_license_definition.dart';
import 'package:ardrive/components/license_details_popover.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/upload/domain/repository/upload_repository.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:reactive_forms/reactive_forms.dart';

import '../blocs/upload/upload_handles/bundle_upload_handle.dart';
import '../pages/drive_detail/components/drive_explorer_item_tile.dart';

Future<void> promptToUpload(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
  required bool isFolderUpload,
  List<IOFile>? files,
}) async {
  final driveDetailCubit = context.read<DriveDetailCubit>();

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
    arnsRepository: context.read<ARNSRepository>(),
    uploadRepository: context.read<UploadRepository>(),
  );

  if (files != null) {
    cubit.selectFiles(files, parentFolderId);
  } else if (isFolderUpload) {
    await cubit.pickFilesFromFolder(
        context: context, parentFolderId: parentFolderId);
  } else {
    cubit.pickFiles(context: context, parentFolderId: parentFolderId);
  }

  final uploadCubit = BlocProvider<UploadCubit>(
    create: (context) => cubit,
  );

  final uploadPaymentMethodBloc = BlocProvider(
    create: (context) => UploadPaymentMethodBloc(
      context.read<ProfileCubit>(),
      context.read<ArDriveUploadPreparationManager>(),
      context.read<ArDriveAuth>(),
    ),
  );

  await showCongestionDependentModalDialog(
    context,
    () {
      if (!context.mounted) {
        return;
      }
      showArDriveDialog(
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
      );
    },
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

  @override
  initState() {
    super.initState();
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
          listener: (context, state) async {
            if (state is EmptyUpload) {
              Navigator.pop(context);
            }

            if (state is UploadComplete || state is UploadWalletMismatch) {
              if (!_isShowingCancelDialog) {
                Navigator.pop(context);
                context.read<FeedbackSurveyCubit>().openRemindMe();
                context.read<ActivityTracker>().setUploading(false);
                context.read<SyncCubit>().startSync();
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
              return _UploadReadyWidget(
                  state: state, driveDetailCubit: widget.driveDetailCubit);
            } else if (state is UploadConfiguringLicense) {
              return _UploadConfiguringLicenseWidget(state: state);
            } else if (state is UploadReviewWithArnsName) {
              return _UploadReviewWithArnsNameWidget(state: state);
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
            } else if (state is AssigningUndername) {
              return const ProgressDialog(
                  title: 'Assigning ArNS Name...', useNewArDriveUI: true);
            } else if (state is UploadReviewWithLicense) {
              if (state.readyState.showArnsNameSelection) {
                return AssignArNSNameModal(
                  driveDetailCubit: widget.driveDetailCubit,
                  justSelectName: true,
                  onSelectionConfirmed: (name) {
                    context.read<UploadCubit>().selectUndernameWithLicense(
                          antRecord: name.selectedName,
                          undername: name.selectedUndername,
                        );
                  },
                  canClose: false,
                  onEmptySelection: (emptySelection) {
                    context.read<UploadCubit>().cancelArnsNameSelection();
                  },
                );
              }

              return _UploadReviewWithLicenseWidget(state: state);
            }
            return const SizedBox();
          },
        ),
      );
}

class StatsScreen extends StatefulWidget {
  final UploadReady readyState;
  final List<ModalAction> modalActions;
  final List<Widget> children;

  final bool hasCloseButton;

  const StatsScreen({
    super.key,
    required this.readyState,
    this.hasCloseButton = true,
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

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return UploadReadyModalBase(
      readyState: widget.readyState,
      hasCloseButton: widget.hasCloseButton,
      actions: widget.modalActions,
      children: [
        files == null
            // TODO: Replace progress indicator with error view
            ? const Center(child: CircularProgressIndicator())
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 156),
                  child: ArDriveScrollBar(
                      controller: _scrollController,
                      alwaysVisible: true,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(right: 8),
                        controller: _scrollController,
                        shrinkWrap: true,
                        itemCount: files!.length,
                        itemBuilder: (BuildContext context, int index) {
                          final file = files![index];
                          if (file is FileV2UploadHandle) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                file.entity.name!,
                                style: typography.paragraphNormal(
                                  fontWeight: ArFontWeight.bold,
                                ),
                              ),
                              leading: Text(
                                filesize(file.size),
                                style: typography.paragraphNormal(
                                  fontWeight: ArFontWeight.semiBold,
                                ),
                              ),
                              trailing: getIconForContentType(
                                file.entity.dataContentType ?? '',
                                size: 20,
                              ),
                            );
                          } else {
                            final bundle = file as BundleUploadHandle;

                            return ListView(
                                padding: const EdgeInsets.only(right: 8),
                                shrinkWrap: true,
                                children: bundle.fileEntities.map((e) {
                                  final file = e;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      file.name!,
                                      style: typography.paragraphNormal(
                                        fontWeight: ArFontWeight.bold,
                                        color: colorTokens.textMid,
                                      ),
                                    ),
                                    trailing: Text(
                                      filesize(file.size),
                                      style: typography.paragraphNormal(
                                        fontWeight: ArFontWeight.semiBold,
                                        color: colorTokens.textMid,
                                      ),
                                    ),
                                    leading: getIconForContentType(
                                      file.dataContentType ?? '',
                                      color: colorTokens.textMid,
                                      size: 20,
                                    ),
                                  );
                                }).toList());
                          }
                        },
                      )),
                ),
              ),
        const Divider(height: 20),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Total Size: ',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textMid,
                ),
              ),
              TextSpan(
                text: filesize(
                  widget.readyState.paymentInfo.totalSize,
                ),
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                  color: colorTokens.textHigh,
                ),
              ),
            ],
          ),
        ),
        const Divider(
          height: 20,
        ),
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
              style: ArDriveTypography.body.smallBold(
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  List<ModalAction> getModalActions(
      BuildContext context, UploadReady state, FormGroup form) {
    String title;
    double? customWidth;

    if (state.arnsCheckboxChecked) {
      title = 'Assign Name';
      customWidth = 160;
    } else {
      title = appLocalizationsOf(context).nextEmphasized;
    }

    return [
      ModalAction(
        action: () => {
          context.read<UploadCubit>().configuringLicenseBack(),
        },
        title: appLocalizationsOf(context).backEmphasized,
      ),
      ModalAction(
        isEnable: form.valid,
        customWidth: customWidth,
        action: () {
          context.read<UploadCubit>().configuringLicenseNext();
        },
        title: title,
      ),
    ];
  }
}

class UploadReadyModalBase extends StatefulWidget {
  final UploadReady readyState;
  final List<ModalAction> actions;
  final List<Widget> children;

  final bool hasCloseButton;
  final double width;

  const UploadReadyModalBase({
    super.key,
    required this.readyState,
    required this.actions,
    required this.children,
    this.hasCloseButton = true,
    this.width = 440,
  });

  @override
  State<UploadReadyModalBase> createState() => _UploadReadyModalBaseState();
}

class _UploadReadyModalBaseState extends State<UploadReadyModalBase> {
  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    return ArDriveScrollBar(
      child: SingleChildScrollView(
        child: BlocBuilder<UploadCubit, UploadState>(
          builder: (context, state) {
            return ArDriveStandardModalNew(
              width: widget.width,
              hasCloseButton: widget.hasCloseButton,
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 185,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          flex: 1,
                          child: Text(
                            appLocalizationsOf(context)
                                .uploadNFiles(widget.readyState.numberOfFiles),
                            style: typography.heading3(
                              fontWeight: ArFontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    ...widget.children,
                  ],
                ),
              ),
              actions: widget.actions,
            );
          },
        ),
      ),
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
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // TODO: Localize
          'License',
          style: typography.paragraphLarge(
            fontWeight: ArFontWeight.semiBold,
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
                      style: ArDriveTypography.body.buttonLargeRegular(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
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
        tooltip:
            // TODO: Localize
            // appLocalizations.of(context).licenseDetails,
            'Show license configuration',
        child: Text.rich(
          TextSpan(
            text: widget.licenseState.meta.nameWithShortName,
            style: ArDriveTypography.body
                .buttonLargeRegular(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                )
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
                      ModalAction(
                        action: () => Navigator.of(context).pop(false),
                        title: appLocalizationsOf(context).cancelEmphasized,
                      ),
                      ...getModalActions(context, state, licenseCategory),
                    ],
                    children: [
                      RepositoryProvider.value(
                        value: context.read<ArDriveUploadPreparationManager>(),
                        child: UploadPaymentMethodView(
                          useDropdown: true,
                          onError: () {
                            context
                                .read<UploadCubit>()
                                .emitErrorFromPreparation();
                          },
                          onTurboTopupSucess: () {
                            context.read<UploadCubit>().startUploadPreparation(
                                  isRetryingToPayWithTurbo: true,
                                );
                          },
                          useNewArDriveUI: true,
                          onUploadMethodChanged: (method, info, canUpload) {
                            context
                                .read<UploadCubit>()
                                .setUploadMethod(method, info, canUpload);
                          },
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
            backgroundColor: Colors.grey[850], // or any other background color
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
              style: ArDriveTypography.body.buttonNormalRegular(),
            ),
            const SizedBox(height: 16),
            Text(appLocalizationsOf(context).conflictingFiles),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Text(
                  state.conflictingFileNames.join(', \n'),
                  style: ArDriveTypography.body.buttonNormalRegular(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!state.areAllFilesConflicting)
          ModalAction(
            action: () => context.read<UploadCubit>().checkConflictingFiles(),
            title: appLocalizationsOf(context).skipEmphasized,
          ),
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).cancelEmphasized,
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
      title: 'Retry Failed Uploads?',
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'There are ${state.conflictingFileNamesForFailedFiles.length} file(s) marked with a red dot, indicating they failed to upload. Would you like to retry uploading these files by replacing the failed versions? This action will only affect the failed uploads and will not alter any successfully uploaded files. Alternatively, you can choose to skip these files and proceed with the others.',
              style: ArDriveTypography.body.buttonNormalRegular(),
            ),
            const SizedBox(height: 16),
            Text(
              'Conflicting files',
              style: ArDriveTypography.body.buttonNormalRegular(),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                itemCount: state.conflictingFileNamesForFailedFiles.length,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  final file = state.conflictingFileNamesForFailedFiles[index];
                  final typography = ArDriveTypographyNew.of(context);
                  final colorTokens =
                      ArDriveTheme.of(context).themeData.colorTokens;

                  return ListTile(
                    title: Text(file,
                        style: typography.paragraphNormal(
                          color: colorTokens.textMid,
                        )),
                    leading: getIconForContentType(
                      getFileExtensionFromFileName(fileName: file),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () => context
              .read<UploadCubit>()
              .checkConflictingFiles(checkFailedFiles: false),
          title: appLocalizationsOf(context).skipEmphasized,
        ),
        ModalAction(
          action: () => context
              .read<UploadCubit>()
              .prepareUploadPlanAndCostEstimates(
                  uploadAction: UploadActions.skipSuccessfulUploads),
          title: 'Replace failed uploads',
          customWidth: 160,
          customHeight: 60,
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
              style:
                  typography.paragraphNormal(fontWeight: ArFontWeight.semiBold),
            ),
            const SizedBox(height: 16),
            Text(
              appLocalizationsOf(context).conflictingFiles,
              style:
                  typography.paragraphNormal(fontWeight: ArFontWeight.semiBold),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: state.conflictingFileNames.length,
                itemBuilder: (context, index) {
                  final file = state.conflictingFileNames[index];
                  final typography = ArDriveTypographyNew.of(context);

                  return ListTile(
                    title: Text(
                      file,
                      style: typography.paragraphNormal(
                        color: colorTokens.textMid,
                      ),
                    ),
                    leading: getIconForContentType(
                      getFileExtensionFromFileName(fileName: file),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!state.areAllFilesConflicting)
          ModalAction(
            action: () => context
                .read<UploadCubit>()
                .prepareUploadPlanAndCostEstimates(
                    uploadAction: UploadActions.skip),
            title: appLocalizationsOf(context).skipEmphasized,
          ),
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).cancelEmphasized,
        ),
        ModalAction(
          action: () => context
              .read<UploadCubit>()
              .prepareUploadPlanAndCostEstimates(
                  uploadAction: UploadActions.replace),
          title: appLocalizationsOf(context).replaceEmphasized,
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
              style: ArDriveTypography.body.buttonNormalRegular(),
            ),
            const SizedBox(height: 16),
            Text(
              appLocalizationsOf(context).tooLargeForUpload,
              style: ArDriveTypography.body.buttonNormalRegular(),
            ),
            const SizedBox(height: 8),
            Text(
              state.tooLargeFileNames.join(', '),
              style: ArDriveTypography.body.buttonNormalRegular(),
            ),
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).cancelEmphasized,
        ),
        if (state.hasFilesToUpload)
          ModalAction(
            action: () => context
                .read<UploadCubit>()
                .skipLargeFilesAndCheckForConflicts(),
            title: appLocalizationsOf(context).skipEmphasized,
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
            if (state is UploadPreparationInitialized &&
                (state as UploadPreparationInitialized).showLoadingFiles) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
            ],
            if (state is UploadPreparationInProgress &&
                (state as UploadPreparationInProgress).isArConnect)
              Text(
                appLocalizationsOf(context).arConnectRemainOnThisTab,
                style: ArDriveTypography.body.buttonNormalBold(),
              )
            else
              Text(
                appLocalizationsOf(context).thisMayTakeAWhile,
                style: ArDriveTypography.body.buttonNormalBold(),
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
  });

  final UploadReady state;
  final DriveDetailCubit driveDetailCubit;
  @override
  Widget build(BuildContext context) {
    if (state.showArnsNameSelection) {
      return AssignArNSNameModal(
        driveDetailCubit: driveDetailCubit,
        justSelectName: true,
        onSelectionConfirmed: (name) {
          context
              .read<UploadCubit>()
              .selectUndername(name.selectedName, name.selectedUndername);
        },
        canClose: false,
        onEmptySelection: (emptySelection) {
          context.read<UploadCubit>().cancelArnsNameSelection();
        },
      );
    }

    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ReactiveForm(
      formGroup: context.watch<UploadCubit>().licenseCategoryForm,
      child: ReactiveFormConsumer(
        builder: (_, form, __) {
          final LicenseCategory? licenseCategory =
              form.control('licenseCategory').value;
          return StatsScreen(
            readyState: state,
            // Don't show on first screen?
            hasCloseButton: false,
            modalActions: [
              ModalAction(
                action: () => Navigator.of(context).pop(false),
                title: appLocalizationsOf(context).cancelEmphasized,
              ),
              ...getModalActions(context, state, licenseCategory),
            ],
            children: [
              if (state.params.containsSupportedImageTypeForThumbnailGeneration)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      ArDriveCheckBox(
                        title: 'Upload with thumbnails',
                        useNewIcons: true,
                        checked: context
                            .read<ConfigService>()
                            .config
                            .uploadThumbnails,
                        titleStyle: typography.paragraphLarge(),
                        onChange: (value) {
                          context
                              .read<UploadCubit>()
                              .changeUploadThumbnailOption(value);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: ArDriveIconButton(
                          icon: ArDriveIcons.info(
                            color: colorTokens.textMid,
                          ),
                          tooltip:
                              'Uploading with thumbnails is free, but may make your upload take longer.\nYou can always attach a thumbnail later.',
                        ),
                      )
                    ],
                  ),
                ),
              if (state.loadingArNSNamesError)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        'Error loading ARNS names',
                        style: typography.paragraphLarge(
                          fontWeight: ArFontWeight.semiBold,
                          color: colorTokens.textRed,
                        ),
                      ),
                    ],
                  ),
                ),
              if (state.loadingArNSNames)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Text(
                        'Loading ArNS names...',
                        style: typography.paragraphLarge(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    ],
                  ),
                ),
              if (state.showArnsCheckbox && !state.loadingArNSNames)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Row(
                    children: [
                      ArDriveCheckBox(
                        title: 'Assign an ARNS name',
                        checked: state.arnsCheckboxChecked,
                        useNewIcons: true,
                        titleStyle: typography.paragraphLarge(),
                        onChange: (value) {
                          context
                              .read<UploadCubit>()
                              .changeShowArnsNameSelection(value);
                        },
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ArDriveIcons.license1(),
                        const SizedBox(width: 8),
                        Text(
                          'License',
                          style: typography.paragraphLarge(
                            fontWeight: ArFontWeight.semiBold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ArDriveClickArea(
                          tooltip: 'Learn more about licenses',
                          child: GestureDetector(
                            onTap: () {
                              openUrl(url: Resources.licenseHelpLink);
                            },
                            child: ArDriveIcons.question(
                              color: colorTokens.textLow,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 32.0),
                      child: ReactiveForm(
                        formGroup:
                            context.watch<UploadCubit>().licenseCategoryForm,
                        child: ReactiveDropdownField<LicenseCategory?>(
                          alignment: AlignmentDirectional.centerStart,
                          isExpanded: true,
                          formControlName: 'licenseCategory',
                          decoration: InputDecoration(
                            labelStyle: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                            ),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          showErrors: (control) =>
                              control.dirty && control.invalid,
                          validationMessages:
                              kValidationMessages(appLocalizationsOf(context)),
                          items: [null, ...LicenseCategory.values].map(
                            (value) {
                              return DropdownMenuItem(
                                value: value,
                                child: Text(
                                  licenseCategoryNames[value] ?? 'None',
                                  style: typography.paragraphNormal(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: colorTokens.textMid,
                                  ),
                                ),
                              );
                            },
                          ).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (state.paymentInfo.isFreeThanksToTurbo) ...[
                const SizedBox(height: 8),
                Text(
                  appLocalizationsOf(context).freeTurboTransaction,
                  style: typography.paragraphNormal(
                    color: colorTokens.textMid,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (!state.paymentInfo.isFreeThanksToTurbo) ...[
                RepositoryProvider.value(
                  value: context.read<ArDriveUploadPreparationManager>(),
                  child: UploadPaymentMethodView(
                    useDropdown: true,
                    onError: () {
                      context.read<UploadCubit>().emitErrorFromPreparation();
                    },
                    onTurboTopupSucess: () {
                      context.read<UploadCubit>().startUploadPreparation(
                          isRetryingToPayWithTurbo: true);
                    },
                    onUploadMethodChanged: (method, info, canUpload) {
                      context
                          .read<UploadCubit>()
                          .setUploadMethod(method, info, canUpload);
                    },
                    useNewArDriveUI: true,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

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
    return StatsScreen(
      readyState: readyState,
      modalActions: [
        ModalAction(
          action: () => {
            context.read<UploadCubit>().reviewBack(),
          },
          title: appLocalizationsOf(context).backEmphasized,
        ),
        ModalAction(
          action: () {
            context.read<UploadCubit>().reviewUpload();
          },
          title: appLocalizationsOf(context).uploadEmphasized,
        ),
      ],
      children: [
        if (state.readyState.params.arnsUnderName != null) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ArNS Name: ',
                style: ArDriveTypography.body.smallRegular(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
                ),
              ),
              Text(
                getLiteralARNSRecordName(
                  state.readyState.params.arnsUnderName!,
                ),
                style: ArDriveTypography.body.buttonLargeRegular(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                ),
              ),
            ],
          ),
        ],
        LicenseReviewInfo(licenseState: state.licenseState),
      ],
    );
  }
}

class _UploadReviewWithArnsNameWidget extends StatelessWidget {
  const _UploadReviewWithArnsNameWidget({required this.state});

  final UploadReviewWithArnsName state;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return StatsScreen(
      readyState: state.readyState,
      modalActions: [
        ModalAction(
          action: () => {
            context.read<UploadCubit>().reviewBack(),
          },
          title: appLocalizationsOf(context).backEmphasized,
        ),
        ModalAction(
          action: () {
            context.read<UploadCubit>().reviewUpload();
          },
          title: appLocalizationsOf(context).uploadEmphasized,
        ),
      ],
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ArNS Name: ',
              style: typography.paragraphLarge(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textMid,
              ),
            ),
            Text(
              getLiteralARNSRecordName(
                state.readyState.params.arnsUnderName!,
              ),
              style: typography.paragraphLarge(
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ],
        ),
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
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            if (state.isArConnect)
              Text(
                appLocalizationsOf(context).arConnectRemainOnThisTab,
                style: ArDriveTypography.body.buttonNormalRegular(),
              )
            else
              Text(appLocalizationsOf(context).thisMayTakeAWhile,
                  style: ArDriveTypography.body.buttonNormalRegular()),
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
            title: appLocalizationsOf(context).okEmphasized,
          ),
        ],
      );
    }

    return ArDriveStandardModalNew(
      hasCloseButton: true,
      width: state.failedTasks != null ? kLargeDialogWidth : kMediumDialogWidth,
      title: 'Problem with Upload',
      description: appLocalizationsOf(context).yourUploadFailed,
      content: state.failedTasks != null
          ? _failedUploadList(state.failedTasks!)
          : null,
      actions: state.failedTasks == null
          ? null
          : [
              ModalAction(
                action: () => Navigator.of(context).pop(false),
                title: 'Do Not Fix',
              ),
              ModalAction(
                action: () {
                  context.read<UploadCubit>().retryUploads();
                },
                title: 'Re-Upload',
              ),
            ],
    );
  }

  Widget _failedUploadList(List<UploadTask> tasks) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
          maxHeight: 256 * 1.5, minWidth: kLargeDialogWidth),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'It seems there was a partial failure uploading the following file(s). The file(s) will show as failed in your drive. Please re-upload to fix.',
                style: ArDriveTypography.body.buttonLargeBold()),
            const SizedBox(height: 8),
            Expanded(
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
                                  size: 20,
                                )
                              : file is ARFSFolderUploadMetatadata
                                  ? getIconForContentType(
                                      'folder',
                                      size: 20,
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
                                      style: ArDriveTypography.body
                                          .buttonNormalBold(
                                            color: ArDriveTheme.of(context)
                                                .themeData
                                                .colors
                                                .themeFgDefault,
                                          )
                                          .copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                    AnimatedSwitcher(
                                      duration: const Duration(seconds: 1),
                                      child: Column(
                                        children: [
                                          if (file is ARFSFileUploadMetadata)
                                            Text(
                                              filesize(file.size),
                                              style: ArDriveTypography.body
                                                  .buttonNormalBold(
                                                color: ArDriveTheme.of(context)
                                                    .themeData
                                                    .colors
                                                    .themeFgOnDisabled,
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
      title: appLocalizationsOf(context).warningEmphasized,
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
              style: ArDriveTypography.body.buttonNormalRegular(),
            ),
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).cancelEmphasized,
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
          title: appLocalizationsOf(context).proceed,
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
      title: 'Upload canceled',
      description: 'Your upload was canceled',
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).okEmphasized,
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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return ArDriveStandardModalNew(
      actions: [
        if (state.progress.hasUploadInProgress)
          ModalAction(
            action: () {
              onChangeCancelWarning(true);
              final cubit = context.read<UploadCubit>();

              showAnimatedDialog(
                context,
                content: BlocBuilder<UploadCubit, UploadState>(
                  bloc: cubit,
                  builder: (context, state) {
                    if (state is UploadComplete) {
                      // TODO: localize
                      return ArDriveStandardModalNew(
                        title: 'Upload complete',
                        description:
                            'Your upload is complete. You can not cancel it anymore.',
                        actions: [
                          ModalAction(
                            action: () {
                              // parent modal
                              Navigator.pop(context);

                              Navigator.pop(context);

                              onChangeCancelWarning(false);
                            },
                            title: 'Ok',
                          ),
                        ],
                      );
                    }
                    // TODO: localize
                    return ArDriveStandardModalNew(
                      title: 'Warning',
                      description:
                          'Cancelling this upload may still result in a charge to your wallet. Do you still wish to proceed?',
                      actions: [
                        ModalAction(
                          action: () {
                            onChangeCancelWarning(false);
                            Navigator.pop(context);
                          },
                          title: 'No',
                        ),
                        ModalAction(
                          action: () {
                            onChangeCancelWarning(false);
                            cubit.cancelUpload();
                            Navigator.pop(context);
                          },
                          title: 'Yes',
                        ),
                      ],
                    );
                  },
                ),
              );
            },
            // TODO: localize
            title: state.isCanceling
                ? 'Canceling...'
                : appLocalizationsOf(context).cancelEmphasized,
          ),
      ],
      width: kLargeDialogWidth,
      title:
          '${appLocalizationsOf(context).uploadingNFiles(state.progress.numberOfItems)} ${(state.totalProgress * 100).toStringAsFixed(2)}%',
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

                      String? progressText;
                      String status = '';

                      // TODO: localize
                      switch (task.status) {
                        case UploadStatus.notStarted:
                          status = 'Not started';
                          break;
                        case UploadStatus.inProgress:
                          status = 'In progress';
                          break;
                        case UploadStatus.paused:
                          status = 'Paused';
                          break;
                        case UploadStatus.creatingMetadata:
                          status =
                              'We are preparing your upload. Preparation step 1/2';
                          break;
                        case UploadStatus.encryting:
                          status = 'Encrypting';
                          break;
                        case UploadStatus.finalizing:
                          status = 'Finalizing upload';
                          break;
                        case UploadStatus.complete:
                          status = 'Complete';
                          break;
                        case UploadStatus.failed:
                          status = 'Failed';
                          break;
                        case UploadStatus.preparationDone:
                          status = 'Preparation done';
                          break;
                        case UploadStatus.canceled:
                          status = 'Canceled';
                          break;
                        case UploadStatus.creatingBundle:
                          status =
                              'We are preparing your upload. Preparation step 2/2';
                        case UploadStatus.uploadingThumbnail:
                          status = 'Uploading thumbnail...';
                          break;
                        case UploadStatus.assigningUndername:
                          if (task is FileUploadTask) {
                            status =
                                'Assigning ArNS Name: ${task.metadata.assignedName}...';
                          }
                          break;
                      }

                      final statusAvailableForShowingProgress =
                          task.status == UploadStatus.failed ||
                              task.status == UploadStatus.inProgress ||
                              task.status == UploadStatus.complete ||
                              task.status == UploadStatus.finalizing;

                      if (task.isProgressAvailable) {
                        if (statusAvailableForShowingProgress) {
                          if (task.uploadItem != null) {
                            progressText =
                                '${filesize(((task.uploadItem!.size) * task.progress).ceil())}/${filesize(task.uploadItem!.size)}';
                          }
                        }
                      } else {
                        if (task.status == UploadStatus.inProgress) {
                          // TODO: localize
                          progressText =
                              'Your upload is in progress, but for large files the progress it not available. Please wait...';
                        }
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
                                        size: 20,
                                      )
                                    : file is ARFSFolderUploadMetatadata
                                        ? getIconForContentType(
                                            'folder',
                                            size: 20,
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
                                              fontWeight: ArFontWeight.bold,
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
                                          if (progressText != null)
                                            Text(
                                              progressText,
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
                                                          .colors
                                                          .themeFgDefault,
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
            'Total uploaded: ${filesize(state.progress.totalUploaded)} of ${filesize(state.progress.totalSize)}',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textMid,
            ),
          ),
          // TODO: localize
          Text(
            'Files uploaded: ${state.progress.numberOfUploadedItems} of ${state.progress.numberOfItems}',
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

List<ModalAction> getModalActions(
    BuildContext context, UploadReady state, LicenseCategory? licenseCategory) {
  if (licenseCategory != null) {
    return [
      ModalAction(
        isEnable: state.isNextButtonEnabled,
        action: () {
          context.read<UploadCubit>().initialScreenNext(
                licenseCategory: licenseCategory,
              );
        },
        title: 'CONFIGURE',
      ),
    ];
  } else if (state.arnsCheckboxChecked) {
    return [
      ModalAction(
        isEnable: state.isNextButtonEnabled,
        customWidth: 160,
        action: () {
          context.read<UploadCubit>().initialScreenUpload();
        },
        title: 'ASSIGN NAME',
      ),
    ];
  }

  return [
    ModalAction(
      isEnable: state.isNextButtonEnabled,
      action: () {
        context.read<UploadCubit>().initialScreenUpload();
      },
      title: appLocalizationsOf(context).uploadEmphasized,
    ),
  ];
}

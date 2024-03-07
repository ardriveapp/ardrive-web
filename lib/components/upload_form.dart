import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/blocs/upload/enums/conflicting_files_actions.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/payment_method/view/upload_payment_method_view.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/blocs/upload/upload_handles/file_v2_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/components/file_picker_modal.dart';
import 'package:ardrive/components/license/cc_type_form.dart';
import 'package:ardrive/components/license/udl_params_form.dart';
import 'package:ardrive/components/license_details_popover.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:pst/pst.dart';
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
  final selectedFiles = <UploadFile>[];
  final io = ArDriveIO();
  IOFolder? ioFolder;
  if (files == null) {
    if (isFolderUpload) {
      ioFolder = await io.pickFolder();
      final ioFiles = await ioFolder.listFiles();

      final isMobilePlatform = AppPlatform.isMobile;
      final shouldUseRelativePath =
          isMobilePlatform && ioFolder.path.isNotEmpty;
      final relativeTo =
          shouldUseRelativePath ? getDirname(ioFolder.path) : null;

      final uploadFiles = ioFiles
          .map(
            (file) => UploadFile(
              ioFile: file,
              parentFolderId: parentFolderId,
              relativeTo: relativeTo,
            ),
          )
          .toList();
      selectedFiles.addAll(uploadFiles);
    } else {
      // Display multiple options on Mobile
      // Open file picker on Web
      final ioFiles = kIsWeb
          ? await io.pickFiles(fileSource: FileSource.fileSystem)
          // ignore: use_build_context_synchronously
          : await showMultipleFilesFilePickerModal(context);
      final uploadFiles = ioFiles
          .map((file) =>
              UploadFile(ioFile: file, parentFolderId: parentFolderId))
          .toList();
      selectedFiles.addAll(uploadFiles);
      ioFolder = null;
    }
  } else {
    selectedFiles.addAll(files.map((file) {
      return UploadFile(
        ioFile: file,
        parentFolderId: parentFolderId,
      );
    }));
  }

  // ignore: use_build_context_synchronously
  await showCongestionDependentModalDialog(
    context,
    () => showArDriveDialog(
      context,
      content: RepositoryProvider(
        create: (context) => ArDriveUploadPreparationManager(
          uploadPreparePaymentOptions: UploadPaymentEvaluator(
            appConfig: context.read<ConfigService>().config,
            auth: context.read<ArDriveAuth>(),
            turboBalanceRetriever: TurboBalanceRetriever(
              paymentService: context.read<PaymentService>(),
            ),
            turboUploadCostCalculator: TurboUploadCostCalculator(
              priceEstimator: TurboPriceEstimator(
                wallet: context.read<ArDriveAuth>().currentUser.wallet,
                costCalculator: TurboCostCalculator(
                  paymentService: context.read<PaymentService>(),
                ),
                paymentService: context.read<PaymentService>(),
              ),
              turboCostCalculator: TurboCostCalculator(
                paymentService: context.read<PaymentService>(),
              ),
            ),
            uploadCostEstimateCalculatorForAR:
                UploadCostEstimateCalculatorForAR(
              arweaveService: context.read<ArweaveService>(),
              pstService: context.read<PstService>(),
              arCostToUsd: ConvertArToUSD(
                arweave: context.read<ArweaveService>(),
              ),
            ),
          ),
          uploadPreparer: UploadPreparer(
            uploadPlanUtils: UploadPlanUtils(
              crypto: ArDriveCrypto(),
              arweave: context.read<ArweaveService>(),
              turboUploadService: context.read<TurboUploadService>(),
              driveDao: context.read<DriveDao>(),
            ),
          ),
        ),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<UploadCubit>(
              create: (context) => UploadCubit(
                activityTracker: context.read<ActivityTracker>(),
                folder: ioFolder,
                arDriveUploadManager:
                    context.read<ArDriveUploadPreparationManager>(),
                uploadFileSizeChecker: context.read<UploadFileSizeChecker>(),
                driveId: driveId,
                parentFolderId: parentFolderId,
                files: selectedFiles,
                profileCubit: context.read<ProfileCubit>(),
                pst: context.read<PstService>(),
                driveDao: context.read<DriveDao>(),
                uploadFolders: isFolderUpload,
                auth: context.read<ArDriveAuth>(),
                licenseService: context.read<LicenseService>(),
              )..startUploadPreparation(),
            ),
            BlocProvider(
              create: (context) => UploadPaymentMethodBloc(
                context.read<ProfileCubit>(),
                context.read<ArDriveUploadPreparationManager>(),
                context.read<ArDriveAuth>(),
              ),
            ),
          ],
          child: const UploadForm(),
        ),
      ),
      barrierDismissible: false,
    ),
  );
}

class UploadForm extends StatefulWidget {
  const UploadForm({Key? key}) : super(key: key);

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
            if (state is UploadComplete || state is UploadWalletMismatch) {
              if (!_isShowingCancelDialog) {
                Navigator.pop(context);
                context.read<FeedbackSurveyCubit>().openRemindMe();
                context.read<ActivityTracker>().setUploading(false);
                context.read<SyncCubit>().startSync();
              }
            } else if (state is UploadPreparationInitialized) {
              context.read<UploadCubit>().verifyFilesAboveWarningLimit();
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
              return ArDriveStandardModal(
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
                        appLocalizationsOf(context)
                            .foldersWithTheSameNameAlreadyExists(
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
                      action: () =>
                          context.read<UploadCubit>().checkConflictingFiles(),
                      title: appLocalizationsOf(context).skipEmphasized,
                    ),
                  ModalAction(
                    action: () => Navigator.of(context).pop(false),
                    title: appLocalizationsOf(context).cancelEmphasized,
                  ),
                ],
              );
            } else if (state is UploadFileConflict) {
              return ArDriveStandardModal(
                  title: appLocalizationsOf(context)
                      .duplicateFiles(state.conflictingFileNames.length),
                  content: SizedBox(
                    width: kMediumDialogWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appLocalizationsOf(context)
                              .filesWithTheSameNameAlreadyExists(
                            state.conflictingFileNames.length,
                          ),
                          style: ArDriveTypography.body.buttonNormalRegular(),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          appLocalizationsOf(context).conflictingFiles,
                          style: ArDriveTypography.body.buttonNormalRegular(),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: SingleChildScrollView(
                            child: Text(
                              state.conflictingFileNames.join(', \n'),
                              style:
                                  ArDriveTypography.body.buttonNormalRegular(),
                            ),
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
                  ]);
            } else if (state is UploadFileTooLarge) {
              return ArDriveStandardModal(
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
                            : appLocalizationsOf(context)
                                .filesTooLargeExplanationMobile,
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
            } else if (state is UploadPreparationInProgress ||
                state is UploadPreparationInitialized) {
              return ArDriveStandardModal(
                title: appLocalizationsOf(context).preparingUpload,
                content: SizedBox(
                  width: kMediumDialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      if (state is UploadPreparationInProgress &&
                          state.isArConnect)
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
            } else if (state is UploadReady) {
              return ReactiveForm(
                formGroup: context.watch<UploadCubit>().licenseCategoryForm,
                child: ReactiveFormConsumer(builder: (_, form, __) {
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
                      licenseCategory == null
                          ? ModalAction(
                              isEnable: state.isNextButtonEnabled,
                              action: () {
                                context
                                    .read<UploadCubit>()
                                    .initialScreenUpload();
                              },
                              title:
                                  appLocalizationsOf(context).uploadEmphasized,
                            )
                          : ModalAction(
                              isEnable: state.isNextButtonEnabled,
                              action: () {
                                context.read<UploadCubit>().initialScreenNext(
                                      licenseCategory: licenseCategory,
                                    );
                              },
                              title:
                                  // TODO: Localize
                                  // appLocalizationsOf(context).configureEmphasized,
                                  'CONFIGURE',
                            ),
                    ],
                    children: [
                      RepositoryProvider.value(
                        value: context.read<ArDriveUploadPreparationManager>(),
                        child: UploadPaymentMethodView(
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
                          onUploadMethodChanged: (method, info, canUpload) {
                            context
                                .read<UploadCubit>()
                                .setUploadMethod(method, info, canUpload);
                          },
                          params: state.params,
                        ),
                      ),
                      SizedBox(
                        child: ReactiveForm(
                          formGroup:
                              context.watch<UploadCubit>().licenseCategoryForm,
                          child: ReactiveDropdownField<LicenseCategory?>(
                            alignment: AlignmentDirectional.centerStart,
                            isExpanded: true,
                            formControlName: 'licenseCategory',
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              label: Text(
                                'License',
                                // TODO: Localize
                                // appLocalizationsOf(context).licenseType,
                                style: ArDriveTheme.of(context)
                                    .themeData
                                    .textFieldTheme
                                    .inputTextStyle
                                    .copyWith(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgDisabled,
                                      fontSize: 16,
                                    ),
                              ),
                              focusedBorder: InputBorder.none,
                            ),
                            showErrors: (control) =>
                                control.dirty && control.invalid,
                            validationMessages: kValidationMessages(
                                appLocalizationsOf(context)),
                            items: [null, ...LicenseCategory.values].map(
                              (value) {
                                return DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    licenseCategoryNames[value] ?? 'None',
                                    // TODO: Localize
                                    // appLocalizationsOf(context).none,
                                  ),
                                );
                              },
                            ).toList(),
                          ),
                        ),
                      ),
                      ArDriveClickArea(
                        child: GestureDetector(
                          onTap: () {
                            openUrl(
                              url: Resources.learnMoreAboutLicensing,
                            );
                          },
                          child: Text(
                            'Learn More about Licensing',
                            style: ArDriveTypography.body
                                .buttonNormalRegular()
                                .copyWith(decoration: TextDecoration.underline),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              );
            } else if (state is UploadConfiguringLicense) {
              final headingText =
                  'Configure ${licenseCategoryNames[state.licenseCategory]}';
              switch (state.licenseCategory) {
                case LicenseCategory.udl:
                  final udlParamsForm =
                      context.watch<UploadCubit>().licenseUdlParamsForm;
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
                  final ccTypeForm =
                      context.watch<UploadCubit>().licenseCcTypeForm;
                  return ConfiguringLicenseScreen(
                    headingText: headingText,
                    readyState: state.readyState,
                    formGroup: ccTypeForm,
                    child: CcTypeForm(formGroup: ccTypeForm),
                  );
                default:
                  return const Text('Unsupported license category');
              }
            } else if (state is UploadReviewWithLicense) {
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
                  LicenseReviewInfo(licenseState: state.licenseState),
                ],
              );
            } else if (state is UploadSigningInProgress) {
              return ArDriveStandardModal(
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
                            style:
                                ArDriveTypography.body.buttonNormalRegular()),
                    ],
                  ),
                ),
              );
            } else if (state is UploadInProgressUsingNewUploader) {
              return _uploadUsingNewUploader(state: state);
            } else if (state is UploadInProgress) {
              final numberOfFilesInBundles =
                  state.uploadPlan.bundleUploadHandles.isNotEmpty
                      ? state.uploadPlan.bundleUploadHandles
                          .map((e) => e.numberOfFiles)
                          .reduce((value, element) => value += element)
                      : 0;
              final numberOfV2Files =
                  state.uploadPlan.fileV2UploadHandles.length;

              final v2Files =
                  state.uploadPlan.fileV2UploadHandles.values.toList();
              final bundles = state.uploadPlan.bundleUploadHandles.toList();
              final files = [...v2Files, ...bundles];

              return ArDriveStandardModal(
                title:
                    '${appLocalizationsOf(context).uploadingNFiles(numberOfFilesInBundles + numberOfV2Files)} ${(state.progress * 100).toStringAsFixed(2)}%',
                content: SizedBox(
                  width: kMediumDialogWidth,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 256),
                    child: Scrollbar(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: files.length,
                        itemBuilder: (BuildContext context, int index) {
                          if (files[index] is FileV2UploadHandle) {
                            final file = files[index] as FileV2UploadHandle;
                            return Column(
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Row(
                                    children: [
                                      Text(
                                        file.entity.name!,
                                        style: ArDriveTypography.body
                                            .buttonNormalBold(
                                          color: ArDriveTheme.of(context)
                                              .themeData
                                              .colors
                                              .themeFgDefault,
                                        ),
                                      ),
                                      Text(
                                        filesize(file.entity.size),
                                        style: ArDriveTypography.body
                                            .buttonNormalBold(
                                          color: ArDriveTheme.of(context)
                                              .themeData
                                              .colors
                                              .themeFgDefault,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${filesize(file.uploadedSize)}/${filesize(file.size)}',
                                    style: ArDriveTypography.body
                                        .buttonNormalRegular(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgOnDisabled,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          } else {
                            final file = files[index] as BundleUploadHandle;
                            return Column(
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (var fileEntity in file.fileEntities)
                                        Row(
                                          children: [
                                            Text(
                                              fileEntity.name!,
                                              style: ArDriveTypography.body
                                                  .buttonNormalBold(
                                                color: ArDriveTheme.of(context)
                                                    .themeData
                                                    .colors
                                                    .themeFgDefault,
                                              ),
                                            ),
                                            Text(
                                              filesize(fileEntity.size),
                                              style: ArDriveTypography.body
                                                  .buttonNormalBold(
                                                color: ArDriveTheme.of(context)
                                                    .themeData
                                                    .colors
                                                    .themeFgDefault,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${filesize(file.uploadedSize)}/${filesize(file.size)}',
                                    style: ArDriveTypography.body
                                        .buttonNormalRegular(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgOnDisabled,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              );
            } else if (state is UploadCanceled) {
              return ArDriveStandardModal(
                title: 'Upload canceled',
                description: 'Your upload was canceled',
                actions: [
                  ModalAction(
                    action: () => Navigator.of(context).pop(false),
                    title: appLocalizationsOf(context).okEmphasized,
                  ),
                ],
              );
            } else if (state is UploadFailure) {
              logger.e('Upload failed: ${state.error}');
              if (state.error == UploadErrors.turboTimeout) {
                return ArDriveStandardModal(
                  title: appLocalizationsOf(context).uploadFailed,
                  description:
                      appLocalizationsOf(context).yourUploadFailedTurboTimeout,
                  actions: [
                    ModalAction(
                      action: () => Navigator.of(context).pop(false),
                      title: appLocalizationsOf(context).okEmphasized,
                    ),
                  ],
                );
              }

              return ArDriveStandardModal(
                hasCloseButton: true,
                width: state.failedTasks != null
                    ? kLargeDialogWidth
                    : kMediumDialogWidth,
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
            } else if (state is UploadShowingWarning) {
              // TODO: Fix use of startUpload
              return ArDriveStandardModal(
                title: appLocalizationsOf(context).warningEmphasized,
                content: SizedBox(
                  width: kMediumDialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appLocalizationsOf(context)
                            .weDontRecommendUploadsAboveASafeLimit(
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
            return const SizedBox();
          },
        ),
      );

  Widget _uploadUsingNewUploader({
    required UploadInProgressUsingNewUploader state,
  }) {
    final progress = state.progress;
    return ArDriveStandardModal(
      actions: [
        if (state.progress.hasUploadInProgress)
          ModalAction(
            action: () {
              _isShowingCancelDialog = true;
              final cubit = context.read<UploadCubit>();

              showAnimatedDialog(
                context,
                content: BlocBuilder<UploadCubit, UploadState>(
                  bloc: cubit,
                  builder: (context, state) {
                    if (state is UploadComplete) {
                      // TODO: localize
                      return ArDriveStandardModal(
                        title: 'Upload complete',
                        description:
                            'Your upload is complete. You can not cancel it anymore.',
                        actions: [
                          ModalAction(
                            action: () {
                              // parent modal
                              Navigator.pop(context);

                              Navigator.pop(context);
                            },
                            title: 'Ok',
                          ),
                        ],
                      );
                    }
                    // TODO: localize
                    return ArDriveStandardModal(
                      title: 'Warning',
                      description:
                          'Cancelling this upload may still result in a charge to your wallet. Do you still wish to proceed?',
                      actions: [
                        ModalAction(
                          action: () => Navigator.pop(context),
                          title: 'No',
                        ),
                        ModalAction(
                          action: () {
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
                                        size: 24,
                                      )
                                    : file is ARFSFolderUploadMetatadata
                                        ? getIconForContentType(
                                            'folder',
                                            size: 24,
                                          )
                                        : null,
                                contentPadding: EdgeInsets.zero,
                                title: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      flex: 1,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            file.name,
                                            style: ArDriveTypography.body
                                                .buttonNormalBold(
                                                  color:
                                                      ArDriveTheme.of(context)
                                                          .themeData
                                                          .colors
                                                          .themeFgDefault,
                                                )
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight.bold),
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
                                                        style: ArDriveTypography
                                                            .body
                                                            .buttonNormalBold(
                                                          color: ArDriveTheme
                                                                  .of(context)
                                                              .themeData
                                                              .colors
                                                              .themeFgOnDisabled,
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
                                    Flexible(
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
                                            Flexible(
                                              flex: 2,
                                              child: ArDriveProgressBar(
                                                height: 4,
                                                indicatorColor:
                                                    _getUploadStatusColor(
                                                  context,
                                                  task,
                                                ),
                                                percentage: task.progress,
                                              ),
                                            ),
                                            Flexible(
                                              child: Text(
                                                '${(task.progress * 100).toInt()}%',
                                                style: ArDriveTypography.body
                                                    .buttonNormalBold(
                                                  color:
                                                      ArDriveTheme.of(context)
                                                          .themeData
                                                          .colors
                                                          .themeFgDefault,
                                                ),
                                              ),
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
            style: ArDriveTypography.body
                .buttonNormalBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          // TODO: localize
          Text(
            'Files uploaded: ${state.progress.numberOfUploadedItems} of ${state.progress.numberOfItems}',
            style: ArDriveTypography.body
                .buttonNormalBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          // TODO: localize
          if (state.progress.hasUploadInProgress)
            Text(
              'Upload speed: ${filesize(state.progress.calculateUploadSpeed().toInt())}/s',
              style: ArDriveTypography.body.buttonNormalBold(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault),
            ),
        ],
      ),
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
                                  size: 24,
                                )
                              : file is ARFSFolderUploadMetatadata
                                  ? getIconForContentType(
                                      'folder',
                                      size: 24,
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

  Color _getUploadStatusColor(
      BuildContext context, UploadTask uploadStatusColor) {
    final themeColors = ArDriveTheme.of(context).themeData.colors;

    if (uploadStatusColor.status == UploadStatus.failed) {
      return themeColors.themeErrorDefault;
    } else if (uploadStatusColor.progress == 1) {
      return themeColors.themeSuccessDefault;
    } else {
      return themeColors.themeFgDefault;
    }
  }
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
    return UploadReadyModalBase(
      readyState: widget.readyState,
      hasCloseButton: widget.hasCloseButton,
      actions: widget.modalActions,
      children: [
        files == null
            ? const Center(child: CircularProgressIndicator())
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: ArDriveScrollBar(
                      controller: _scrollController,
                      alwaysVisible: true,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 0),
                        controller: _scrollController,
                        shrinkWrap: true,
                        itemCount: files!.length,
                        itemBuilder: (BuildContext context, int index) {
                          final file = files![index];
                          if (file is FileV2UploadHandle) {
                            return Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${file.entity.name!} ',
                                    style: ArDriveTypography.body.smallBold(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgSubtle,
                                    ),
                                  ),
                                ),
                                Text(
                                  filesize(file.size),
                                  style: ArDriveTypography.body.smallRegular(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgMuted,
                                  ),
                                ),
                              ],
                            );
                          } else {
                            final bundle = file as BundleUploadHandle;

                            return ListView(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                children: bundle.fileEntities.map((e) {
                                  return Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '${e.name!} ',
                                          style:
                                              ArDriveTypography.body.smallBold(
                                            color: ArDriveTheme.of(context)
                                                .themeData
                                                .colors
                                                .themeFgSubtle,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        filesize(e.size),
                                        style:
                                            ArDriveTypography.body.smallRegular(
                                          color: ArDriveTheme.of(context)
                                              .themeData
                                              .colors
                                              .themeFgMuted,
                                        ),
                                      ),
                                    ],
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
                text: 'Size: ',
                style: ArDriveTypography.body.buttonNormalRegular(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeFgOnDisabled,
                ),
              ),
              TextSpan(
                text: filesize(
                  widget.readyState.paymentInfo.totalSize,
                ),
                style: ArDriveTypography.body
                    .buttonNormalBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Text.rich(
          TextSpan(
            children: [
              if (widget.readyState.paymentInfo.isFreeThanksToTurbo) ...[
                TextSpan(
                  text: appLocalizationsOf(context).freeTurboTransaction,
                  style: ArDriveTypography.body.buttonNormalRegular(),
                ),
              ]
            ],
            style: ArDriveTypography.body.buttonNormalRegular(),
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 10),
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
            actions: [
              ModalAction(
                action: () => {
                  context.read<UploadCubit>().configuringLicenseBack(),
                },
                title: appLocalizationsOf(context).backEmphasized,
              ),
              ModalAction(
                isEnable: form.valid,
                action: () {
                  context.read<UploadCubit>().configuringLicenseNext();
                },
                title: appLocalizationsOf(context).nextEmphasized,
              ),
            ],
            children: [
              Text(
                headingText,
                style: ArDriveTypography.body.smallBold(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ));
  }
}

class UploadReadyModalBase extends StatelessWidget {
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
    this.width = 408,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveScrollBar(
      child: SingleChildScrollView(
        child: ArDriveStandardModal(
          title: appLocalizationsOf(context)
              .uploadNFiles(readyState.numberOfFiles),
          width: width,
          hasCloseButton: hasCloseButton,
          content: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 185),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
          actions: actions,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // TODO: Localize
          'License',
          style: ArDriveTypography.body.smallRegular(
            color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
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
                      )),
            if (licenseState.meta.licenseType != LicenseType.unknown)
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '   '),
                    TextSpan(
                      text: 'View',
                      style: ArDriveTypography.body
                          .buttonLargeRegular(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgSubtle,
                          )
                          .copyWith(
                            decoration: TextDecoration.underline,
                          ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final url =
                              'https://arweave.net/${licenseState.meta.licenseDefinitionTxId}';
                          await openUrl(url: url);
                        },
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

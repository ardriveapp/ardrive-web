import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/blocs/upload/enums/conflicting_files_actions.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/blocs/upload/upload_handles/file_v2_upload_handle.dart';
import 'package:ardrive/components/file_picker_modal.dart';
import 'package:ardrive/components/payment_method_selector_widget.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import '../blocs/upload/upload_handles/bundle_upload_handle.dart';
import '../pages/drive_detail/components/drive_explorer_item_tile.dart';

Future<void> promptToUpload(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
  required bool isFolderUpload,
}) async {
  final selectedFiles = <UploadFile>[];
  final io = ArDriveIO();
  IOFolder? ioFolder;
  if (isFolderUpload) {
    ioFolder = await io.pickFolder();
    final ioFiles = await ioFolder.listFiles();
    final uploadFiles = ioFiles.map((file) {
      return UploadFile(
        ioFile: file,
        parentFolderId: parentFolderId,
        relativeTo: ioFolder!.path.isEmpty ? null : getDirname(ioFolder.path),
      );
    }).toList();
    selectedFiles.addAll(uploadFiles);
  } else {
    // Display multiple options on Mobile
    // Open file picker on Web
    final ioFiles = kIsWeb
        ? await io.pickFiles(fileSource: FileSource.fileSystem)
        // ignore: use_build_context_synchronously
        : await showMultipleFilesFilePickerModal(context);

    final uploadFiles = ioFiles
        .map((file) => UploadFile(ioFile: file, parentFolderId: parentFolderId))
        .toList();

    selectedFiles.addAll(uploadFiles);
  }

  // ignore: use_build_context_synchronously
  await showCongestionDependentModalDialog(
    context,
    () => showArDriveDialog(
      context,
      content: BlocProvider<UploadCubit>(
        create: (context) => UploadCubit(
          folder: ioFolder,
          arDriveUploadManager: ArDriveUploadPreparationManager(
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
          uploadFileChecker: context.read<UploadFileChecker>(),
          driveId: driveId,
          parentFolderId: parentFolderId,
          files: selectedFiles,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          turbo: context.read<TurboUploadService>(),
          pst: context.read<PstService>(),
          driveDao: context.read<DriveDao>(),
          uploadFolders: isFolderUpload,
          auth: context.read<ArDriveAuth>(),
        )..startUploadPreparation(),
        child: const UploadForm(),
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
  final _scrollController = ScrollController();
  bool _isShowingCancelDialog = false;

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<UploadCubit, UploadState>(
        listener: (context, state) async {
          if (state is UploadComplete || state is UploadWalletMismatch) {
            if (!_isShowingCancelDialog) {
              Navigator.pop(context);
              context.read<FeedbackSurveyCubit>().openRemindMe();
            }
          } else if (state is UploadPreparationInitialized) {
            context.read<UploadCubit>().verifyFilesAboveWarningLimit();
          }
          if (state is UploadWalletMismatch) {
            Navigator.pop(context);
            context.read<ProfileCubit>().logoutProfile();
          }
        },
        buildWhen: (previous, current) => current is! UploadComplete,
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
            final numberOfFilesInBundles =
                state.uploadPlanForAR.bundleUploadHandles.isNotEmpty
                    ? state.uploadPlanForAR.bundleUploadHandles
                        .map((e) => e.numberOfFiles)
                        .reduce((value, element) => value += element)
                    : 0;
            final numberOfV2Files =
                state.uploadPlanForAR.fileV2UploadHandles.length;

            logger.d(
              ' is button to upload enabled: ${state.isButtonToUploadEnabled}',
            );

            final v2Files = state.uploadPlanForAR.fileV2UploadHandles.values
                .map((e) => e)
                .toList();

            final bundles = state.uploadPlanForAR.bundleUploadHandles.toList();

            final files = [...v2Files, ...bundles];

            return ArDriveStandardModal(
              width: 408,
              title: appLocalizationsOf(context)
                  .uploadNFiles(numberOfFilesInBundles + numberOfV2Files),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 256),
                      child: ArDriveScrollBar(
                          controller: _scrollController,
                          alwaysVisible: true,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(top: 0),
                            controller: _scrollController,
                            shrinkWrap: true,
                            itemCount: files.length,
                            itemBuilder: (BuildContext context, int index) {
                              final file = files[index];
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
                                              style: ArDriveTypography.body
                                                  .smallBold(
                                                color: ArDriveTheme.of(context)
                                                    .themeData
                                                    .colors
                                                    .themeFgSubtle,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            filesize(e.size),
                                            style: ArDriveTypography.body
                                                .smallRegular(
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
                  const SizedBox(height: 8),
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
                            state.uploadSize,
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
                        if (state.isFreeThanksToTurbo) ...[
                          TextSpan(
                            text: appLocalizationsOf(context)
                                .freeTurboTransaction,
                            style: ArDriveTypography.body.buttonNormalRegular(),
                          ),
                        ]
                      ],
                      style: ArDriveTypography.body.buttonNormalRegular(),
                    ),
                  ),
                  const Divider(
                    height: 20,
                  ),
                  if (state.uploadIsPublic) ...{
                    Text(
                      appLocalizationsOf(context).filesWillBeUploadedPublicly(
                        numberOfFilesInBundles + numberOfV2Files,
                      ),
                      style: ArDriveTypography.body.buttonNormalRegular(),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                  },
                  PaymentMethodSelector(
                    uploadMethod: state.uploadMethod,
                    costEstimateTurbo: state.costEstimateTurbo,
                    costEstimateAr: state.costEstimateAr,
                    hasNoTurboBalance: state.isZeroBalance,
                    isTurboUploadPossible: state.isTurboUploadPossible,
                    arBalance: state.arBalance,
                    sufficientArBalance: state.sufficientArBalance,
                    turboCredits: state.turboCredits,
                    sufficentCreditsBalance: state.sufficentCreditsBalance,
                    isFreeThanksToTurbo: state.isFreeThanksToTurbo,
                    onArSelect: () {
                      context
                          .read<UploadCubit>()
                          .setUploadMethod(UploadMethod.ar);
                    },
                    onTurboSelect: () {
                      context
                          .read<UploadCubit>()
                          .setUploadMethod(UploadMethod.turbo);
                    },
                    onTurboTopupSucess: () {
                      context.read<UploadCubit>().startUploadPreparation(
                            isRetryingToPayWithTurbo: true,
                          );
                    },
                  ),
                ],
              ),
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(false),
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
                ModalAction(
                  isEnable: state.isButtonToUploadEnabled,
                  action: () {
                    context.read<UploadCubit>().startUpload(
                          uploadPlanForAr: state.uploadPlanForAR,
                          uploadPlanForTurbo: state.uploadPlanForTurbo,
                        );
                  },
                  title: appLocalizationsOf(context).uploadEmphasized,
                ),
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
                          style: ArDriveTypography.body.buttonNormalRegular()),
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
            final numberOfV2Files = state.uploadPlan.fileV2UploadHandles.length;

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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
              title: appLocalizationsOf(context).uploadFailed,
              description: appLocalizationsOf(context).yourUploadFailed,
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(false),
                  title: appLocalizationsOf(context).okEmphasized,
                ),
              ],
            );
          } else if (state is UploadShowingWarning) {
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
                        filesize(publicFileSafeSizeLimit),
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
                  action: () =>
                      context.read<UploadCubit>().checkFilesAboveLimit(),
                  title: appLocalizationsOf(context).proceed,
                ),
              ],
            );
          }
          return const SizedBox();
        },
      );

  Widget _uploadUsingNewUploader({
    required UploadInProgressUsingNewUploader state,
  }) {
    final progress = state.progress;
    return ArDriveStandardModal(
      actions: [
        ModalAction(
          action: () {
            if (state.uploadMethod == UploadMethod.ar &&
                state.progress.task.any(
                    (element) => element.status == UploadStatus.inProgress)) {
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
            } else {
              context.read<UploadCubit>().cancelUpload();
            }
          },
          // TODO: localize
          title: state.isCanceling
              ? 'Canceling...'
              : appLocalizationsOf(context).cancelEmphasized,
        ),
      ],
      width: kLargeDialogWidth,
      title:
          '${appLocalizationsOf(context).uploadingNFiles(state.progress.getNumberOfItems())} ${(state.totalProgress * 100).toStringAsFixed(2)}%',
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
                    itemCount: progress.task.length,
                    itemBuilder: (BuildContext context, int index) {
                      final task = progress.task[index];

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

                      if (task.isProgressAvailable) {
                        if (task.status == UploadStatus.inProgress ||
                            task.status == UploadStatus.complete ||
                            task.status == UploadStatus.failed) {
                          progressText =
                              '${filesize(((task.uploadItem!.size) * task.progress).ceil())}/${filesize(task.uploadItem!.size)}';
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
                                                Text(
                                                  status,
                                                  style: ArDriveTypography.body
                                                      .buttonNormalBold(
                                                    color:
                                                        ArDriveTheme.of(context)
                                                            .themeData
                                                            .colors
                                                            .themeFgOnDisabled,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (progressText != null)
                                            Text(
                                              progressText,
                                              style: ArDriveTypography.body
                                                  .buttonNormalRegular(
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
                                              (task.status ==
                                                      UploadStatus.failed ||
                                                  task.status ==
                                                      UploadStatus.inProgress ||
                                                  task.status ==
                                                      UploadStatus
                                                          .complete)) ...[
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
                                          const SizedBox(
                                            width: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          Divider(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgSubtle
                                .withOpacity(0.5),
                            thickness: 0.5,
                            height: 8,
                          )
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
            'Files uploaded: ${state.progress.tasksContentCompleted()} of ${state.progress.tasksContentLength()}',
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
            'Upload speed: ${filesize(state.progress.calculateUploadSpeed().toInt())}/s',
            style: ArDriveTypography.body.buttonNormalBold(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeFgDefault),
          ),
          const SizedBox(
            height: 8,
          ),
          if (state.containsLargeTurboUpload)
            Align(
              alignment: Alignment.center,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Warning!',
                    style: ArDriveTypography.body
                        .buttonLargeBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeErrorMuted,
                        )
                        .copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text('Leaving this page may result in a failed upload',
                      style: ArDriveTypography.body.buttonLargeBold())
                ],
              ),
            )
        ],
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

import 'dart:async';
import 'dart:math';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/blocs/upload/enums/conflicting_files_actions.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/blocs/upload/upload_handles/file_v2_upload_handle.dart';
import 'package:ardrive/components/file_picker_modal.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
        : await showMultipleFilesFilePickerModal(context);

    final uploadFiles = ioFiles
        .map((file) => UploadFile(ioFile: file, parentFolderId: parentFolderId))
        .toList();

    selectedFiles.addAll(uploadFiles);
  }

  // ignore: use_build_context_synchronously
  await showCongestionDependentModalDialog(
    context,
    () => showAnimatedDialog(
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
                  wallet: context.read<ArDriveAuth>().currentUser!.wallet,
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
  UploadMethod? _uploadMethod;

  @override
  initState() {
    super.initState();
    startRandomMessageStream();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<UploadCubit, UploadState>(
        listener: (context, state) async {
          if (state is UploadComplete || state is UploadWalletMismatch) {
            Navigator.pop(context);
            context.read<FeedbackSurveyCubit>().openRemindMe();
          } else if (state is UploadPreparationInitialized) {
            context.read<UploadCubit>().verifyFilesAboveWarningLimit();
          }
          if (state is UploadWalletMismatch) {
            Navigator.pop(context);
            context.read<ProfileCubit>().logoutProfile();
          }
        },
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

            _uploadMethod = state.uploadMethod;

            logger.d(
                ' is button to upload enabled: ${state.isButtonToUploadEnabled}');

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
                  if (!state.isFreeThanksToTurbo) ...[
                    Text(
                      'Payment method:',
                      style: ArDriveTypography.body.buttonLargeBold(),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    ArDriveRadioButtonGroup(
                      size: 15,
                      onChanged: (index, value) {
                        switch (index) {
                          case 0:
                            if (value) {
                              context
                                  .read<UploadCubit>()
                                  .setUploadMethod(UploadMethod.ar);
                            }
                            break;

                          case 1:
                            if (value) {
                              context
                                  .read<UploadCubit>()
                                  .setUploadMethod(UploadMethod.turbo);
                            }
                            break;
                        }
                      },
                      options: [
                        RadioButtonOptions(
                          value: state.uploadMethod == UploadMethod.ar,
                          // TODO: Localization
                          text:
                              'Cost: ${winstonToAr(state.costEstimateAr.totalCost)} AR',
                          textStyle: ArDriveTypography.body.buttonLargeBold(),
                        ),
                        if (state.costEstimateTurbo != null &&
                            state.isTurboUploadPossible)
                          RadioButtonOptions(
                            value: state.uploadMethod == UploadMethod.turbo,
                            // TODO: Localization
                            text: state.isZeroBalance
                                ? ''
                                : 'Cost: ${winstonToAr(state.costEstimateTurbo!.totalCost)} Credits',
                            textStyle: ArDriveTypography.body.buttonLargeBold(),
                            content: state.isZeroBalance
                                ? GestureDetector(
                                    onTap: () {
                                      showTurboModal(context, onSuccess: () {
                                        context
                                            .read<UploadCubit>()
                                            .startUploadPreparation(
                                              isRetryingToPayWithTurbo: true,
                                            );
                                      });
                                    },
                                    child: ArDriveClickArea(
                                      child: RichText(
                                        text: TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Use Turbo Credits',
                                              style: ArDriveTypography.body
                                                  .buttonLargeBold(
                                                    color:
                                                        ArDriveTheme.of(context)
                                                            .themeData
                                                            .colors
                                                            .themeFgDefault,
                                                  )
                                                  .copyWith(
                                                    decoration: TextDecoration
                                                        .underline,
                                                  ),
                                            ),
                                            TextSpan(
                                              text: ' for faster uploads.',
                                              style: ArDriveTypography.body
                                                  .buttonLargeBold(
                                                color: ArDriveTheme.of(context)
                                                    .themeData
                                                    .colors
                                                    .themeFgDefault,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : null,
                          )
                      ],
                      builder: (index, radioButton) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          radioButton,
                          Padding(
                            padding: const EdgeInsets.only(left: 24.0),
                            child: Text(
                              index == 0
                                  ? 'Wallet Balance: ${state.arBalance} AR'
                                  : 'Turbo Balance: ${state.turboCredits} Credits',
                              style: ArDriveTypography.body.buttonNormalBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _getInsufficientBalanceMessage(
                      sufficentCreditsBalance: state.sufficentCreditsBalance,
                      sufficientArBalance: state.sufficientArBalance,
                    ),
                  ]
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
                // decoration: BoxDecoration(
                //   // rounded border
                //   borderRadius: BorderRadius.circular(8),
                //   border: Border.all(
                //     color: ArDriveTheme.of(context)
                //         .themeData
                //         .colors
                //         .themeFgOnDisabled,
                //     width: 1.5,
                //   ),
                // ),
                padding: const EdgeInsets.all(8),
                child: Scrollbar(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: progress.task.length,
                    itemBuilder: (BuildContext context, int index) {
                      final task = progress.task[index];

                      String progressText;
                      String status = '';

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
                        case UploadStatus.bundling:
                          status = 'Bundling';
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
                      }

                      if (task.isProgressAvailable && task.dataItem != null) {
                        progressText =
                            '${filesize(((task.dataItem!.size) * task.progress).ceil())}/${filesize(task.dataItem!.size)}';
                      } else {
                        progressText =
                            'Your upload is in progress, but for large files the progress it not available. Please wait...';
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
                                            child: Text(
                                              status,
                                              style: ArDriveTypography.body
                                                  .buttonNormalBold(
                                                color: ArDriveTheme.of(context)
                                                    .themeData
                                                    .colors
                                                    .themeFgOnDisabled,
                                              ),
                                            ),
                                          ),
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
                                        children: [
                                          Flexible(
                                            flex: 2,
                                            child: ArDriveProgressBar(
                                              height: 4,
                                              indicatorColor: task.status ==
                                                      UploadStatus.failed
                                                  ? ArDriveTheme.of(context)
                                                      .themeData
                                                      .colors
                                                      .themeErrorDefault
                                                  : task.progress == 1
                                                      ? ArDriveTheme.of(context)
                                                          .themeData
                                                          .colors
                                                          .themeSuccessDefault
                                                      : ArDriveTheme.of(context)
                                                          .themeData
                                                          .colors
                                                          .themeFgDefault,
                                              percentage: task.progress,
                                            ),
                                          ),
                                          Flexible(
                                            child: Text(
                                              '${(task.progress * 100).toInt()}%',
                                              style: ArDriveTypography.body
                                                  .buttonNormalBold(
                                                color: ArDriveTheme.of(context)
                                                    .themeData
                                                    .colors
                                                    .themeFgDefault,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 8,
                                          ),
                                          if (task.status ==
                                              UploadStatus.failed)
                                            SizedBox(
                                              height: 24,
                                              child: ArDriveClickArea(
                                                child: GestureDetector(
                                                  onTap: () {
                                                    context
                                                        .read<UploadCubit>()
                                                        .retryTask(
                                                          state.controller,
                                                          task,
                                                        );
                                                  },
                                                  child: ArDriveIcons.refresh(),
                                                ),
                                              ),
                                            )
                                        ],
                                      ),
                                    ),

                                    // TODO: get the correct size
                                    // Text(
                                    //   filesize(
                                    //     task.dataItem!.dataItemResult
                                    //         .dataItemSize,
                                    //   ),
                                    //   style: ArDriveTypography.body
                                    //       .buttonNormalBold(
                                    //     color: ArDriveTheme.of(context)
                                    //         .themeData
                                    //         .colors
                                    //         .themeFgDefault,
                                    //   ),
                                    // ),
                                  ],
                                ),
                                // trailing: Text(
                                //   progressText,
                                //   style: ArDriveTypography.body
                                //       .buttonNormalRegular(
                                //     color: ArDriveTheme.of(context)
                                //         .themeData
                                //         .colors
                                //         .themeFgOnDisabled,
                                //   ),
                                // ),,
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

  void startRandomMessageStream() async {
    final random = Random();
    while (true) {
      final index = random.nextInt(arDriveFacts.length);
      randomMessageController.add(arDriveFacts[index]);
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  final StreamController<String> randomMessageController =
      StreamController<String>.broadcast();

  static const List<String> arDriveFacts = [
    'ArDrive lets you store your data forever!',
    'Your data is encrypted and only you can access it.',
    'Pay once, store forever. No subscription fees.',
    "ArDrive is built on top of Arweave's blockchain protocol.",
    'Benefit from decentralized storage without the hassle.',
  ];

  Widget _getInsufficientBalanceMessage({
    required bool sufficientArBalance,
    required bool sufficentCreditsBalance,
  }) {
    if (_uploadMethod == UploadMethod.turbo &&
        !sufficentCreditsBalance &&
        sufficientArBalance) {
      return GestureDetector(
        onTap: () {
          showTurboModal(context, onSuccess: () {
            context.read<UploadCubit>().startUploadPreparation(
                  isRetryingToPayWithTurbo: true,
                );
          });
        },
        child: ArDriveClickArea(
          child: Text.rich(
            TextSpan(
              text: 'Insufficient Credit balance for purchase. ',
              style: ArDriveTypography.body.captionBold(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
              ),
              children: [
                TextSpan(
                  text: 'Add Credits',
                  style: ArDriveTypography.body
                      .captionBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeErrorDefault,
                      )
                      .copyWith(decoration: TextDecoration.underline),
                ),
                TextSpan(
                  text: ' to use Turbo.',
                  style: ArDriveTypography.body.captionBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (_uploadMethod == UploadMethod.ar && !sufficientArBalance) {
      return Text(
        'Insufficient AR balance for purchase.',
        style: ArDriveTypography.body.captionBold(
          color: ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
        ),
      );
    } else if (!sufficentCreditsBalance && !sufficientArBalance) {
      return GestureDetector(
        onTap: () {
          showTurboModal(context, onSuccess: () {
            context.read<UploadCubit>().startUploadPreparation(
                  isRetryingToPayWithTurbo: true,
                );
          });
        },
        child: ArDriveClickArea(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text:
                      'Insufficient balance to pay for this upload. You can either',
                  style: ArDriveTypography.body.captionBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  ),
                ),
                TextSpan(
                  text: ' add Turbo credits to your profile',
                  style: ArDriveTypography.body
                      .captionBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeErrorDefault,
                      )
                      .copyWith(
                        decoration: TextDecoration.underline,
                      ),
                ),
                TextSpan(
                  text: ' or use AR',
                  style: ArDriveTypography.body.captionBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorDefault,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const SizedBox();
  }
}

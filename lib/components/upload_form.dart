import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/blocs/upload/enums/conflicting_files_actions.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/components/file_picker_modal.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToUpload(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
  required bool isFolderUpload,
}) async {
  final selectedFiles = <UploadFile>[];
  final io = ArDriveIO();
  if (isFolderUpload) {
    final ioFolder = await io.pickFolder();
    final ioFiles = await ioFolder.listFiles();
    final uploadFiles = ioFiles.map((file) {
      return UploadFile(
        ioFile: file,
        parentFolderId: parentFolderId,
        relativeTo: ioFolder.path.isEmpty ? null : getDirname(ioFolder.path),
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
          arDriveUploadManager: ArDriveUploadPreparationManager(
            uploadPreparePaymentOptions: UploadPaymentEvaluator(
              appConfig: context.read<ConfigService>().config,
              auth: context.read<ArDriveAuth>(),
              turboBalanceRetriever: TurboBalanceRetriever(
                paymentService: context.read<PaymentService>(),
              ),
              turboUploadCostCalculator: TurboUploadCostCalculator(
                priceEstimator: TurboPriceEstimator(
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
          turboBalanceRetriever: TurboBalanceRetriever(
            paymentService: context.read<PaymentService>(),
          ),
        )..startUploadPreparation(),
        child: UploadForm(),
      ),
      barrierDismissible: false,
    ),
  );
}

class UploadForm extends StatefulWidget {
  UploadForm({Key? key}) : super(key: key);

  @override
  State<UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends State<UploadForm> {
  final _scrollController = ScrollController();
  bool? useTurbo;

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

            useTurbo ??= state.sufficentCreditsBalance;

            return ArDriveStandardModal(
              width: 408,
              title: appLocalizationsOf(context)
                  .uploadNFiles(numberOfFilesInBundles + numberOfV2Files),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 256),
                    child: ArDriveScrollBar(
                      controller: _scrollController,
                      alwaysVisible: true,
                      child: ListView(
                        controller: _scrollController,
                        shrinkWrap: true,
                        children: [
                          for (final file in state
                              .uploadPlanForAR.fileV2UploadHandles.values) ...{
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  file.entity.name!,
                                  style:
                                      ArDriveTypography.body.buttonNormalBold(),
                                ),
                                subtitle: Text(
                                  filesize(
                                    file.size,
                                  ),
                                  style:
                                      ArDriveTypography.body.buttonNormalBold(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgOnDisabled,
                                  ),
                                )),
                          },
                          for (final bundle
                              in state.uploadPlanForAR.bundleUploadHandles) ...{
                            for (final fileEntity in bundle.fileEntities) ...{
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  fileEntity.name!,
                                  style:
                                      ArDriveTypography.body.buttonNormalBold(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgDefault,
                                  ),
                                ),
                                subtitle: Text(
                                  filesize(fileEntity.size),
                                  style:
                                      ArDriveTypography.body.buttonNormalBold(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgOnDisabled,
                                  ),
                                ),
                              ),
                            },
                          },
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  },
                  if (!state.isFreeThanksToTurbo) ...[
                    Text(
                      'Payment method:',
                      style: ArDriveTypography.body.buttonLargeBold(),
                    ),
                    const SizedBox(
                      height: 16,
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
                          isEnabled: state.sufficientArBalance,
                          text:
                              'Cost: ${winstonToAr(state.costEstimateAr.totalCost)} AR',
                          textStyle: ArDriveTypography.body.buttonLargeBold(),
                        ),
                        if (state.costEstimateTurbo != null &&
                            state.isTurboUploadPossible)
                          RadioButtonOptions(
                            value: state.uploadMethod == UploadMethod.turbo,
                            isEnabled: state.sufficentCreditsBalance,
                            text: state.isZeroBalance
                                ? ''
                                : 'Cost ${winstonToAr(state.costEstimateTurbo!.totalCost)} Credits',
                            textStyle: ArDriveTypography.body.buttonLargeBold(),
                            content: state.isZeroBalance
                                ? GestureDetector(
                                    onTap: () {
                                      showTurboModal(context, onSuccess: () {
                                        context
                                            .read<UploadCubit>()
                                            .startUploadPreparation();
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
                                    .themeGbMuted,
                              ),
                            ),
                          ),
                          if (index == 0 &&
                              !state.sufficientArBalance &&
                              !state.isFreeThanksToTurbo) ...{
                            const SizedBox(height: 8),
                            Text(
                              appLocalizationsOf(context)
                                  .insufficientARForUpload,
                              style: ArDriveTypography.body.captionBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeErrorDefault,
                              ),
                            ),
                            // ignore: equal_elements_in_set
                            const SizedBox(height: 8)
                          },
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!state.sufficentCreditsBalance && !state.isZeroBalance)
                      GestureDetector(
                        onTap: () {
                          showTurboModal(context, onSuccess: () {
                            context
                                .read<UploadCubit>()
                                .startUploadPreparation();
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
                      )
                  ]
                ],
              ),
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(false),
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
                ModalAction(
                  isEnable: state.sufficientArBalance ||
                      state.sufficentCreditsBalance ||
                      state.isFreeThanksToTurbo,
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
          } else if (state is UploadInProgress) {
            // return SizedBox();
            final numberOfFilesInBundles =
                state.uploadPlan.bundleUploadHandles.isNotEmpty
                    ? state.uploadPlan.bundleUploadHandles
                        .map((e) => e.numberOfFiles)
                        .reduce((value, element) => value += element)
                    : 0;
            final numberOfV2Files = state.uploadPlan.fileV2UploadHandles.length;

            return ArDriveStandardModal(
              title: appLocalizationsOf(context).uploadingNFiles(
                      numberOfFilesInBundles + numberOfV2Files) +
                  ' Progress: ${(state.progress * 100).toStringAsFixed(2)}%',
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 256),
                  child: Scrollbar(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ArDriveProgressBar(
                          percentage: state.progress,
                          indicatorColor: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
                          backgroundColor: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgOnDisabled,
                        ),
                        for (final file
                            in state.uploadPlan.fileV2UploadHandles.values) ...{
                          Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  file.entity.name!,
                                  style:
                                      ArDriveTypography.body.buttonNormalBold(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgDefault,
                                  ),
                                ),
                                trailing: file.uploadProgress == 1
                                    ? ArDriveIcons.checkCirle()
                                    : SizedBox(),
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
                                // trailing: file.hasError
                                //     ? const Icon(Icons.error)
                                //     : CircularProgressIndicator(
                                //         // Show an indeterminate progress indicator if the upload hasn't started yet as
                                //         // small uploads might never report a progress.
                                //         value: file.uploadProgress != 0
                                //             ? file.uploadProgress
                                //             : null),
                              ),
                              file.uploadProgress < 1
                                  ? ArDriveProgressBar(
                                      height: 5,
                                      indicatorColor: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgDefault,
                                      backgroundColor: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgOnDisabled,
                                      percentage: file.uploadProgress,
                                    )
                                  : const SizedBox(),
                            ],
                          ),
                        },
                        for (final bundle
                            in state.uploadPlan.bundleUploadHandles) ...{
                          Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var fileEntity in bundle.fileEntities)
                                      Text(
                                        fileEntity.name!,
                                        style: ArDriveTypography.body
                                            .buttonNormalRegular(
                                          color: ArDriveTheme.of(context)
                                              .themeData
                                              .colors
                                              .themeFgDefault,
                                        ),
                                      )
                                  ],
                                ),
                                trailing: bundle.uploadProgress == 1
                                    ? ArDriveIcons.checkCirle()
                                    : SizedBox(),
                                subtitle: Text(
                                  '${filesize(bundle.uploadedSize)}/${filesize(bundle.size)}',
                                  style: ArDriveTypography.body
                                      .buttonNormalRegular(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgOnDisabled,
                                  ),
                                ),
                                // trailing: bundle.hasError
                                //     ? const Icon(Icons.error)
                                //     : CircularProgressIndicator(
                                //         // Show an indeterminate progress indicator if the upload hasn't started yet as
                                //         // small uploads might never report a progress.
                                //         value: bundle.uploadProgress != 0
                                //             ? bundle.uploadProgress
                                //             : null,
                                //       ),
                              ),
                              bundle.uploadProgress < 1
                                  ? ArDriveProgressBar(
                                      height: 5,
                                      indicatorColor: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgDefault,
                                      backgroundColor: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgOnDisabled,
                                      percentage: bundle.uploadProgress,
                                    )
                                  : const SizedBox(),
                            ],
                          )
                        },
                      ],
                    ),
                  ),
                ),
              ),
            );
          } else if (state is UploadFailure) {
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
}

late OverlayEntry entry;

showDownloadOverlay({
  required BuildContext context,
  required Widget child,
}) {
  entry = OverlayEntry(
    builder: (context) => Positioned(
      right: 20,
      bottom: 20,
      child: Material(
        borderRadius: BorderRadius.circular(15),
        child: child,
      ),
    ),
  );

  Overlay.of(context).insert(entry);
}

class UploadProgressModal extends StatefulWidget {
  const UploadProgressModal({super.key, required this.cubit});

  final UploadCubit cubit;

  @override
  State<UploadProgressModal> createState() => _UploadProgressModalState();
}

class _UploadProgressModalState extends State<UploadProgressModal> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UploadCubit, UploadState>(
      bloc: widget.cubit,
      builder: (context, state) {
        if (state is UploadInProgress) {
          final numberOfItems = state.uploadPlan.fileV2UploadHandles.length +
              state.uploadPlan.bundleUploadHandles.length;

          double maxHeight = 92 + 40;

          if (numberOfItems > 5) {
            maxHeight += 5 * 40;
          } else {
            maxHeight += numberOfItems * 40;
          }

          return ArDriveCard(
            contentPadding: EdgeInsets.zero,
            backgroundColor:
                ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
            width: 348,
            height: maxHeight,
            content: Column(
              children: [
                Container(
                  color:
                      ArDriveTheme.of(context).themeData.tableTheme.cellColor,
                  height: 40,
                  alignment: Alignment.centerLeft,
                  width: double.maxFinite,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Uploading... (${(state.progress * 100).toStringAsFixed(2)}%)',
                          style: ArDriveTypography.body.buttonLargeBold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                          ),
                        ),
                        ArDriveIcons.x()
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .tableTheme
                        .backgroundColor,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: state.uploadPlan.fileV2UploadHandles.length +
                          state.uploadPlan.bundleUploadHandles.length,
                      itemBuilder: (context, index) {
                        String itemName;

                        if (index <
                            state.uploadPlan.fileV2UploadHandles.length) {
                          itemName = state.uploadPlan.fileV2UploadHandles.values
                              .elementAt(index)
                              .entity
                              .name!;
                        } else {
                          itemName = state.uploadPlan.bundleUploadHandles
                              .elementAt(index -
                                  state.uploadPlan.fileV2UploadHandles.length)
                              .fileEntities
                              .map((e) => e.name!)
                              .join(', ');
                        }

                        return ListTile(
                          leading: ArDriveIcons.file(),
                          title: Text(
                            itemName,
                            style: ArDriveTypography.body.buttonNormalBold(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                )
              ],
            ),
          );
        }
        return const SizedBox();
      },
    );
  }
}

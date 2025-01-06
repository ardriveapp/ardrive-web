import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/arns/presentation/assign_name_modal.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/payment_method/view/upload_payment_method_view.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/core/arfs/utils/arfs_revision_status_utils.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/entities/manifest_data.dart';
import 'package:ardrive/manifest/domain/manifest_repository.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pst/pst.dart';

import '../utils/show_general_dialog.dart';
import 'components.dart';

Future<void> promptToCreateManifest(
  BuildContext context, {
  required Drive drive,
  String? folderId,
  required bool hasPendingFiles,
}) {
  final pst = context.read<PstService>();
  final configService = context.read<ConfigService>();
  return showArDriveDialog(
    context,
    content: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<DriveDetailCubit>()),
        BlocProvider(
          create: (context) => CreateManifestCubit(
            drive: drive,
            profileCubit: context.read<ProfileCubit>(),
            hasPendingFiles: hasPendingFiles,
            folderRepository: context.read<FolderRepository>(),
            auth: context.read<ArDriveAuth>(),
            manifestRepository: ManifestRepositoryImpl(
              context.read<DriveDao>(),
              ArDriveUploader(
                turboUploadUri:
                    Uri.parse(configService.config.defaultTurboUploadUrl!),
                metadataGenerator: ARFSUploadMetadataGenerator(
                  tagsGenerator: ARFSTagsGenetator(
                    appInfoServices: AppInfoServices(),
                  ),
                ),
                arweave: context.read<ArweaveService>().client,
                pstService: pst,
              ),
              context.read<FolderRepository>(),
              ManifestDataBuilder(
                fileRepository: context.read<FileRepository>(),
                folderRepository: context.read<FolderRepository>(),
              ),
              ARFSRevisionStatusUtils(context.read<FileRepository>()),
              context.read<ARNSRepository>(),
              context.read<FileRepository>(),
            ),
            arnsRepository: context.read<ARNSRepository>(),
          ),
        ),
      ],
      child: const CreateManifestForm(),
    ),
  );
}

class CreateManifestForm extends StatefulWidget {
  const CreateManifestForm({super.key});

  @override
  State<CreateManifestForm> createState() => _CreateManifestFormState();
}

class _CreateManifestFormState extends State<CreateManifestForm> {
  final _manifestNameController = TextEditingController();

  bool _isFormValid = false;

  ArDriveTextFieldNew manifestNameForm() {
    final readCubitContext = context.read<CreateManifestCubit>();

    return ArDriveTextFieldNew(
      hintText: appLocalizationsOf(context).manifestName,
      controller: _manifestNameController,
      validator: (value) {
        final validation = validateEntityName(value, context);

        _isFormValid = validation == null;

        setState(() {});

        return validation;
      },
      autofocus: true,
      onFieldSubmitted: (s) {
        readCubitContext.chooseTargetFolder();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocConsumer<CreateManifestCubit, CreateManifestState>(
        listener: (context, state) {
      if (state is CreateManifestPrivacyMismatch) {
        Navigator.pop(context);
      }
    }, builder: (context, state) {
      final textStyle = typography.paragraphNormal(
        color: colorTokens.textLow,
        fontWeight: ArFontWeight.semiBold,
      );

      ArDriveStandardModal errorDialog({required String errorText}) =>
          ArDriveStandardModal(
            width: kMediumDialogWidth,
            title: appLocalizationsOf(context).failedToCreateManifestEmphasized,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(errorText),
                const SizedBox(height: 16),
              ],
            ),
            actions: [
              ModalAction(
                action: () => Navigator.pop(context),
                title: appLocalizationsOf(context).continueEmphasized,
              ),
            ],
          );
      if (state is CreateManifestSuccess) {
        return _createManifestSuccess(context, state);
      }

      if (state is CreateManifestWalletMismatch) {
        Navigator.pop(context);
        return errorDialog(
          errorText:
              appLocalizationsOf(context).walletChangedDuringManifestCreation,
        );
      } else if (state is CreateManifestFailure) {
        Navigator.pop(context);
        return errorDialog(
          errorText:
              appLocalizationsOf(context).manifestTransactionUnexpectedlyFailed,
        );
      } else if (state is CreateManifestPreparingManifest) {
        return ProgressDialog(
          useNewArDriveUI: true,
          title: appLocalizationsOf(context).preparingManifestEmphasized,
        );
      } else if (state is CreateManifestNameConflict) {
        return _createManifestNameConflict(
          contexty: context,
          textStyle: textStyle,
        );
      } else if (state is CreateManifestRevisionConfirm) {
        return _createManifestRevisionConfirm(
          context: context,
          textStyle: textStyle,
        );
      } else if (state is CreateManifestInitial) {
        return _createManifestInitial(
          context: context,
          textStyle: textStyle,
        );
      }
      if (state is CreateManifestUploadInProgress) {
        return ProgressDialog(
          useNewArDriveUI: true,
          title: 'Creating Manifest...',
          progressDescription: Text(
            _getProgressDescription(state.progress),
            style: typography.paragraphLarge(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
        );
      } else if (state is CreateManifestUploadReview) {
        return _createManifestUploadReview(
          state: state,
          context: context,
          textStyle: textStyle,
        );
      } else if (state is CreateManifestFolderLoadSuccess) {
        return _selectFolder(state, context);
      } else if (state is CreateManifestPreparingManifestWithARNS) {
        if (state.showAssignNameModal) {
          return _assignArNSNameModal(
            context: context,
            textStyle: textStyle,
          );
        }

        return _createManifestPreparingManifestWithARNS(
          context: context,
          textStyle: textStyle,
        );
      }

      return const SizedBox();
    });
  }

  Widget _createManifestSuccess(
      BuildContext context, CreateManifestSuccess state) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      content: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ArDriveIcons.checkCirle(
              size: 50,
              color:
                  ArDriveTheme.of(context).themeData.colors.themeSuccessDefault,
            ),
            const SizedBox(height: 16),
            Text(
              'Manifest Created Successfully',
              style: typography.heading3(
                fontWeight: ArFontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (!state.nameAssignedByArNS) ...[
              Text(
                'Your manifest has been created.',
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
            ],
            if (state.nameAssignedByArNS) ...[
              const SizedBox(height: 8),
              Text(
                'Your manifest has been assigned an ArNS name',
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () {
            context.read<DriveDetailCubit>().refreshDriveDataTable();
            Navigator.pop(context);
          },
          title: 'Close',
        ),
      ],
    );
  }

  String _getProgressDescription(CreateManifestUploadProgress progress) {
    switch (progress) {
      case CreateManifestUploadProgress.preparingManifest:
        return 'Preparing Manifest...';
      case CreateManifestUploadProgress.uploadingManifest:
        return 'Uploading Manifest...';
      case CreateManifestUploadProgress.assigningArNS:
        return 'Assigning ArNS Name...';
      case CreateManifestUploadProgress.completed:
        return 'Completed';
    }
  }

  bool _isFolderEmpty(FolderID folderId, FolderNode rootFolderNode) {
    final folderNode = rootFolderNode.searchForFolder(folderId);

    if (folderNode == null) {
      return true;
    }

    return folderNode.isEmpty();
  }

  Widget _assignArNSNameModal({
    required BuildContext context,
    required TextStyle textStyle,
  }) {
    return AssignArNSNameModal(
      driveDetailCubit: context.read<DriveDetailCubit>(),
      justSelectName: true,
      updateARNSRecords: false,
      customLoadingText: 'Fetching ArNS names...',
      customNameSelectionTitle: 'Assign ArNS Name to New Manifest',
      onSelectionConfirmed: (selection) {
        context.read<CreateManifestCubit>().selectArns(
              selection.selectedName,
              selection.selectedUndername,
            );
      },
    );
  }

  Widget _createManifestPreparingManifestWithARNS({
    required BuildContext context,
    required TextStyle textStyle,
  }) {
    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: 'Assign ArNS Name?',
      description:
          'You have ArNS names associated with your address. Do you want to assign one to this new manifest? You can always do this later.',
      actions: [
        ModalAction(
          action: () {
            context.read<CreateManifestCubit>().selectArns(null, null);
          },
          title: 'No',
        ),
        ModalAction(
          action: () async {
            context.read<CreateManifestCubit>().openAssignNameModal();
          },
          title: 'Yes',
        ),
      ],
    );
  }

  Widget _createManifestNameConflict({
    required BuildContext contexty,
    required TextStyle textStyle,
  }) {
    final readCubitContext = context.read<CreateManifestCubit>();

    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: appLocalizationsOf(context).conflictingNameFound,
      content: SizedBox(
        height: 200,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              appLocalizationsOf(context).conflictingManifestFoundChooseNewName,
              style: textStyle,
            ),
            manifestNameForm()
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
              readCubitContext.reCheckConflicts(_manifestNameController.text),
          title: appLocalizationsOf(context).continueEmphasized,
        ),
      ],
    );
  }

  Widget _createManifestRevisionConfirm({
    required BuildContext context,
    required TextStyle textStyle,
  }) {
    final readCubitContext = context.read<CreateManifestCubit>();
    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: appLocalizationsOf(context).conflictingManifestFound,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            appLocalizationsOf(context).conflictingManifestFoundChooseNewName,
            style: textStyle,
          ),
          const SizedBox(height: 16),
        ],
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: appLocalizationsOf(context).cancelEmphasized,
        ),
        ModalAction(
          isEnable: _isFormValid,
          action: () =>
              readCubitContext.confirmRevision(_manifestNameController.text),
          title: appLocalizationsOf(context).continueEmphasized,
        ),
      ],
    );
  }

  Widget _createManifestInitial({
    required BuildContext context,
    required TextStyle textStyle,
  }) {
    final readCubitContext = context.read<CreateManifestCubit>();
    return ArDriveStandardModalNew(
      width: kLargeDialogWidth,
      title: appLocalizationsOf(context).addnewManifestEmphasized,
      actions: [
        ModalAction(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).cancelEmphasized,
        ),
        ModalAction(
          isEnable: _isFormValid,
          action: () => readCubitContext.chooseTargetFolder(),
          title: appLocalizationsOf(context).nextEmphasized,
        ),
      ],
      content: SizedBox(
        height: 180,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              RichText(
                text: TextSpan(children: [
                  TextSpan(
                    text: appLocalizationsOf(context)
                        .aManifestIsASpecialKindOfFile, // trimmed spaces
                    style: textStyle,
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: appLocalizationsOf(context).learnMore,
                    style: textStyle.copyWith(
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => openUrl(
                            url: Resources.manifestLearnMoreLink,
                          ),
                  ),
                ]),
              ),
              manifestNameForm()
            ],
          ),
        ),
      ),
    );
  }

  Widget _createManifestUploadReview({
    required CreateManifestUploadReview state,
    required BuildContext context,
    required TextStyle textStyle,
  }) {
    final readCubitContext = context.read<CreateManifestCubit>();
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final hasPendingFiles = state.folderHasPendingFiles;

    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: hasPendingFiles
          ? appLocalizationsOf(context).filesPending
          : appLocalizationsOf(context).createManifestEmphasized,
      content: SizedBox(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPendingFiles) ...[
              Text(
                appLocalizationsOf(context).filesPendingManifestExplanation,
                style: textStyle,
              ),
              const Divider(
                height: 48,
              ),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 256),
              child: Scrollbar(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      state.manifestName,
                      style: typography.paragraphLarge(
                        color: colorTokens.textHigh,
                        fontWeight: ArFontWeight.bold,
                      ),
                    ),
                    if (state.assignedName != null) ...[
                      RichText(
                        text: TextSpan(
                          style: typography.paragraphNormal(
                            color: colorTokens.textMid,
                          ),
                          children: [
                            TextSpan(
                              text: 'ArNS Name: ',
                              style: typography.paragraphNormal(
                                color: colorTokens.textMid,
                                fontWeight: ArFontWeight.semiBold,
                              ),
                            ),
                            TextSpan(
                              text: state.assignedName,
                              style: typography.paragraphNormal(
                                color: colorTokens.textMid,
                                fontWeight: ArFontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Text(
                      filesize(state.manifestSize),
                      style: textStyle,
                    ),
                    const SizedBox(height: 8),
                    if (state.fallbackTxId != null) ...[
                      RichText(
                        text: TextSpan(
                          style: textStyle,
                          children: [
                            TextSpan(
                              text: 'Fallback TxId\n',
                              style: typography.paragraphLarge(
                                color: colorTokens.textHigh,
                                fontWeight: ArFontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: state.fallbackTxId,
                              style: typography.paragraphSmall(
                                color: colorTokens.textMid,
                                fontWeight: ArFontWeight.semiBold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 48),
            if (state.freeUpload) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  appLocalizationsOf(context).freeTurboTransaction,
                  style: typography.paragraphNormal(
                    color: colorTokens.textMid,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
              ),
            ],
            if (!state.freeUpload) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _paymentOptions(state, context),
              ),
            ],
            Text(
              appLocalizationsOf(context).filesWillBePermanentlyPublicWarning,
              style: textStyle,
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
          isEnable: state.canUpload,
          action: () => readCubitContext.uploadManifest(),
          title: appLocalizationsOf(context).confirmEmphasized,
        ),
      ],
    );
  }

  Widget _paymentOptions(
      CreateManifestUploadReview state, BuildContext context) {
    final readCubitContext = context.read<CreateManifestCubit>();
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return MultiBlocProvider(
      providers: [
        RepositoryProvider(
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
        ),
        BlocProvider(
          create: (context) => UploadPaymentMethodBloc(
            context.read<ProfileCubit>(),
            context.read<ArDriveUploadPreparationManager>(),
            context.read<ArDriveAuth>(),
          )..add(
              PrepareUploadPaymentMethod(
                params: UploadParams(
                  conflictingFiles: {},
                  files: [
                    UploadFile(
                      ioFile: state.manifestFile,
                      parentFolderId: state.parentFolder.id,
                    ),
                  ],
                  foldersByPath: UploadPlanUtils.generateFoldersForFiles([
                    UploadFile(
                      ioFile: state.manifestFile,
                      parentFolderId: state.parentFolder.id,
                    ),
                  ]),
                  targetDrive: state.drive,
                  targetFolder: state.parentFolder,
                  user: context.read<ArDriveAuth>().currentUser,
                  // Theres no thumbnail generation for manifests
                  containsSupportedImageTypeForThumbnailGeneration: false,
                ),
              ),
            ),
        ),
      ],
      child: UploadPaymentMethodView(
        onUploadMethodChanged: (method, methodInfo, canUpload) {
          readCubitContext.selectUploadMethod(
            method,
            methodInfo,
            canUpload,
          );
        },
        onError: () {},
        loadingIndicator: Center(
          child: Column(
            children: [
              Text(
                'Loading payment methods...',
                style: typography.paragraphLarge(
                  color: colorTokens.textHigh,
                  fontWeight: ArFontWeight.bold,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 32),
                child: SizedBox(
                  child: LinearProgressIndicator(),
                ),
              ),
            ],
          ),
        ),
        useNewArDriveUI: true,
      ),
    );
  }

  Widget _selectFolder(
      CreateManifestFolderLoadSuccess state, BuildContext context) {
    final cubit = context.read<CreateManifestCubit>();

    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final items = <Widget>[
      ...state.viewingFolder.subfolders
          .where((element) => !element.isHidden)
          .map(
        (f) {
          final enabled = !_isFolderEmpty(
            f.id,
            context.read<CreateManifestCubit>().rootFolderNode,
          );

          return ArDriveClickArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16),
              child: GestureDetector(
                onTap: enabled
                    ? () {
                        cubit.loadFolder(f.id);
                      }
                    : null,
                child: Row(
                  children: [
                    ArDriveIcons.folderOutline(
                      size: 20,
                      color: enabled
                          ? colorTokens.textHigh
                          : _colorDisabled(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.name,
                        style: typography.paragraphLarge(
                            fontWeight: ArFontWeight.bold,
                            color: enabled
                                ? colorTokens.textHigh
                                : _colorDisabled(context)),
                      ),
                    ),
                    ArDriveIcons.carretRight(
                      size: 24,
                      color: enabled
                          ? colorTokens.textHigh
                          : _colorDisabled(context),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      ...state.viewingFolder.files.where((element) => !element.isHidden).map(
            (f) => Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 16.0,
                horizontal: 16,
              ),
              child: Row(
                children: [
                  ArDriveIcons.file(
                    size: 20,
                    color: _colorDisabled(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.name,
                      style: typography.paragraphLarge(
                        color: _colorDisabled(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    ];

    return ArDriveModalNew(
      constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
      contentPadding: EdgeInsets.zero,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 77,
              alignment: Alignment.centerLeft,
              color: colorTokens.containerL1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    ArDriveClickArea(
                      child: AnimatedContainer(
                        width: !state.viewingRootFolder ? 20 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: GestureDetector(
                          onTap: () {
                            cubit.loadParentFolder();
                          },
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 200),
                            scale: !state.viewingRootFolder ? 1 : 0,
                            child: ArDriveIcons.arrowLeft(
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedPadding(
                      duration: const Duration(milliseconds: 200),
                      padding: !state.viewingRootFolder
                          ? const EdgeInsets.only(left: 14)
                          : const EdgeInsets.only(left: 0),
                      child: Text(
                        appLocalizationsOf(context).targetFolderEmphasized,
                        style: typography.heading5(
                          color: colorTokens.textHigh,
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    ArDriveIconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: ArDriveIcons.x(
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return items[index];
                },
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ArDriveClickArea(
                child: ArDriveTooltip(
                  message: 'Fallback TxId is the TxId of the fallback file.',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Fallback TxId',
                        style: typography.paragraphNormal(
                          color: colorTokens.textLow,
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ArDriveIcons.info(
                        size: 16,
                        color: colorTokens.iconMid,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ArDriveTextFieldNew(
                hintText: 'TxId',
                onChanged: (value) {
                  cubit.setFallbackTxId(value);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null;
                  }

                  return isValidArweaveTxId(value) ? null : 'Invalid TxId';
                },
              ),
            ),
            const Divider(
              height: 24,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ArDriveCard(
                backgroundColor: colorTokens.containerL1,
                borderRadius: 5,
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArDriveIcons.info(size: 16, color: colorTokens.iconHigh),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hidden files are not added into the manifest.',
                        style: typography.paragraphNormal(
                          color: colorTokens.textMid,
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      action: ModalAction(
        isEnable: state.enableManifestCreationButton,
        action: () => cubit.checkForConflicts(_manifestNameController.text),
        title: appLocalizationsOf(context).createHereEmphasized,
      ),
    );
  }

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colorTokens.iconLow;
}

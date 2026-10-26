import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/components/turbo_free_status_message.dart';
import 'package:ardrive/components/turbo_payment_required_dialog.dart';
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
            initialFolderId: folderId,
            profileCubit: context.read<ProfileCubit>(),
            hasPendingFiles: hasPendingFiles,
            folderRepository: context.read<FolderRepository>(),
            auth: context.read<ArDriveAuth>(),
            manifestRepository: ManifestRepositoryImpl(
              context.read<DriveDao>(),
              ArDriveUploader(
                turboUploadUri:
                    Uri.parse(configService.config.defaultTurboUploadUrl!),
                getArweaveForD2n: () => context.read<ArweaveService>().client,
                metadataGenerator: ARFSUploadMetadataGenerator(
                  tagsGenerator: ARFSTagsGenerator(
                    appInfoServices: AppInfoServices(),
                  ),
                ),
                pstService: pst,
              ),
              context.read<FolderRepository>(),
              ManifestDataBuilder(
                fileRepository: context.read<FileRepository>(),
                folderRepository: context.read<FolderRepository>(),
              ),
              ARFSRevisionStatusUtils(context.read<FileRepository>()),
              context.read<FileRepository>(),
            ),
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

  /// The name step (docs/NAMES.md): null while names are off.
  ArNSFlowNameCubit? _names;
  bool _namesStarted = false;
  Future<ArNSFlowOutcome>? _namesApplied;

  /// Builds the name step once, with the names on the deployment it
  /// updates, which move to the new version.
  ArNSFlowNameCubit? _nameStep(CreateManifestUploadReview state) {
    if (_namesStarted) return _names;
    _namesStarted = true;
    final names = _names = createArNSFlowNameCubit(context);
    final existing = state.existingManifestFileId;
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

  @override
  void dispose() {
    _names?.close();
    super.dispose();
  }

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
        readCubitContext.processManifestName(s);
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
      } else if (state is CreateManifestFailure && state.isPaymentError) {
        Navigator.pop(context);
        showTurboPaymentRequiredDialog(context);
      }
    }, builder: (context, state) {
      final textStyle = typography.paragraphNormal(
        color: colorTokens.textLow,
        fontWeight: ArFontWeight.semiBold,
      );

      ArDriveStandardModalNew errorDialog({required String errorText}) =>
          ArDriveStandardModalNew(
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
        final names = _names;
        final dataTxId = state.dataTxId;
        if (names != null && names.hasWork && dataTxId != null) {
          _namesApplied ??= names.applyTo(dataTxId);
          return FutureBuilder<ArNSFlowOutcome>(
            future: _namesApplied,
            builder: (context, outcome) => outcome.hasData
                ? _createManifestSuccess(context, state, names: outcome.data)
                : ProgressDialog(
                    title: appLocalizationsOf(context).arnsSettingTheName,
                  ),
          );
        }
        return _createManifestSuccess(context, state);
      }

      if (state is CreateManifestWalletMismatch) {
        Navigator.pop(context);
        return errorDialog(
          errorText:
              appLocalizationsOf(context).walletChangedDuringManifestCreation,
        );
      } else if (state is CreateManifestFailure && state.isPaymentError) {
        // Pop + payment dialog handled in the listener; render nothing.
        return const SizedBox.shrink();
      } else if (state is CreateManifestFailure) {
        Navigator.pop(context);
        return errorDialog(
          errorText:
              appLocalizationsOf(context).manifestTransactionUnexpectedlyFailed,
        );
      } else if (state is CreateManifestPreparingManifest) {
        return ProgressDialog(
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
        return const ProgressDialog(
          title: 'Loading Folders...',
        );
      } else if (state is CreateManifestNameInput) {
        return _createManifestNameInput(
          context: context,
          textStyle: textStyle,
          state: state,
        );
      }
      if (state is CreateManifestUploadInProgress) {
        return ProgressDialog(
          title: 'Creating deployment...',
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
      }

      return const SizedBox();
    });
  }

  Widget _createManifestSuccess(
    BuildContext context,
    CreateManifestSuccess state, {
    ArNSFlowOutcome? names,
  }) {
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
              color: ArDriveTheme.of(context)
                  .themeData
                  .colorTokens
                  .statusSuccessFg,
            ),
            const SizedBox(height: 16),
            Text(
              'Deployment created successfully',
              style: typography.heading3(
                fontWeight: ArFontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your deployment has been created.',
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            if (names != null && !names.isEmpty) ...[
              const SizedBox(height: 16),
              ArNSFlowNameResult(outcome: names),
            ],
          ],
        ),
      ),
      actions: [
        ModalAction.dismiss(
          action: () {
            context
                .read<DriveDetailCubit>()
                .openFolder(folderId: state.parentFolder.id);
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
        return 'Preparing deployment...';
      case CreateManifestUploadProgress.uploadingManifest:
        return 'Uploading deployment...';
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

  Widget _createManifestNameInput({
    required BuildContext context,
    required TextStyle textStyle,
    required CreateManifestNameInput state,
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
          action: () => readCubitContext
              .processManifestName(_manifestNameController.text),
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
                  ArDriveLink.span(
                    text: appLocalizationsOf(context).learnMore,
                    style: textStyle,
                    color: textStyle.color,
                    external: true,
                    onTap: () => openUrl(
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
    final names = _nameStep(state);
    if (names != null) {
      return BlocBuilder<ArNSNameDialogCubit, ArNSNameDialogState>(
        bloc: names,
        builder: (context, _) => BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
          builder: (context, __) => _reviewModal(
            state: state,
            context: context,
            textStyle: textStyle,
            names: names,
          ),
        ),
      );
    }
    return _reviewModal(state: state, context: context, textStyle: textStyle);
  }

  Widget _reviewModal({
    required CreateManifestUploadReview state,
    required BuildContext context,
    required TextStyle textStyle,
    ArNSFlowNameCubit? names,
  }) {
    final readCubitContext = context.read<CreateManifestCubit>();
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final hasPendingFiles = state.folderHasPendingFiles;

    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      // The name step makes this taller than a laptop screen: without a
      // scroll, Create deployment was pushed below the window.
      scrollableContent: true,
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
                              text: 'Fallback page\n',
                              style: typography.paragraphLarge(
                                color: colorTokens.textHigh,
                                fontWeight: ArFontWeight.bold,
                              ),
                            ),
                            // A transaction ID, whole, so monospace: it wraps
                            // like text rather than taking a fixed width.
                            TextSpan(
                              text: state.fallbackTxId,
                              style: typography.code(
                                color: colorTokens.textMid,
                                fontSize: 11,
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
            TurboFreeStatusMessage(
              status: state.freeStatus,
              padding: const EdgeInsets.only(bottom: 24),
            ),
            if (!state.freeUpload) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _paymentOptions(state, context),
              ),
            ],
            if (names != null) ...[
              ArNSFlowNameSection(cubit: names),
              const SizedBox(height: 24),
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
          isEnable: state.canUpload && (names?.ready ?? true),
          action: () => readCubitContext.uploadManifest(),
          title: appLocalizationsOf(context).createManifestEmphasized,
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
            context.read<PaymentService>(),
            CreditSharingService.fromConfig(context.read<ConfigService>()),
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
                appLocalizationsOf(context).loadingPaymentMethods,
                style: typography.paragraphLarge(
                  color: colorTokens.textHigh,
                  fontWeight: ArFontWeight.bold,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 32),
                child: ArDriveLinearProgress(),
              ),
            ],
          ),
        ),
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
                  message:
                      'The page shown when a path in the deployment does not exist, such as a 404 page.\nEnter the transaction ID of its file.',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Fallback page',
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
                hintText: 'Transaction ID',
                onChanged: (value) {
                  cubit.setFallbackTxId(value);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null;
                  }

                  return isValidArweaveTxId(value)
                      ? null
                      : 'Invalid transaction ID';
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
                        'Hidden files and folders are not added to the deployment.',
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
        action: () => cubit.promptForManifestName(),
        title: appLocalizationsOf(context).nextEmphasized,
      ),
    );
  }

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colorTokens.iconLow;
}

import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/components/turbo_free_status_message.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
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
    // Its work, the upload included, runs in the dialog: a click outside
    // must not close it mid-way.
    barrierDismissible: false,
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
  const CreateManifestForm({super.key, @visibleForTesting this.names});

  /// A name step to use instead of the one built from the app's providers.
  final ArNSFlowNameCubit? names;

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
  void initState() {
    super.initState();
    final given = widget.names;
    if (given != null) {
      _names = given;
      _namesStarted = true;
    }
  }

  @override
  void dispose() {
    _names?.close();
    _manifestNameController.dispose();
    super.dispose();
  }

  bool _isFormValid = false;

  /// Whether a step that writes or pays has been asked for and has not come
  /// back. Set before the call: the cubit emits its busy state only after
  /// awaiting its checks, so a fast second press would start a second step.
  bool _submitting = false;

  Future<void> _submit(Future<void> Function() step) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await step();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The deployment's name, on the folder screen and again on the name
  /// conflict screen, where it is asked for anew.
  ArDriveTextFieldNew manifestNameForm({
    required void Function(String name) onSubmit,
  }) {
    return ArDriveTextFieldNew(
      isEnabled: !_submitting,
      label: appLocalizationsOf(context).manifestName,
      controller: _manifestNameController,
      validator: (value) {
        final validation = validateEntityName(value, context);

        _isFormValid = validation == null;

        setState(() {});

        return validation;
      },
      autofocus: true,
      onFieldSubmitted: (name) {
        if (_isFormValid && !_submitting) onSubmit(name);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CreateManifestCubit, CreateManifestState>(
        listener: (context, state) {
      if (state is CreateManifestPrivacyMismatch) {
        Navigator.pop(context);
      }
    }, builder: (context, state) {
      final l10n = appLocalizationsOf(context);
      final typography = ArDriveTypographyNew.of(context);
      final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

      if (state is CreateManifestSuccess) {
        final names = _names;
        final dataTxId = state.dataTxId;
        if (names != null && names.hasWork && dataTxId != null) {
          _namesApplied ??= names.applyTo(dataTxId);
          return FutureBuilder<ArNSFlowOutcome>(
            future: _namesApplied,
            // An error here still ends in the success screen: the deployment
            // exists, and a wait with nothing to press is a trap.
            builder: (context, outcome) => outcome.hasData || outcome.hasError
                ? _createManifestSuccess(
                    context,
                    state,
                    names: outcome.data,
                    // The deployment exists, so this is the success screen;
                    // the name the person chose is not set, and they are
                    // told.
                    nameFailed: outcome.hasError,
                  )
                : ProgressDialog(
                    title: l10n.arnsSettingTheName,
                  ),
          );
        }
        return _createManifestSuccess(context, state);
      }

      if (state is CreateManifestWalletMismatch ||
          state is CreateManifestFailure) {
        return _failureModal(context, state);
      } else if (state is CreateManifestPreparingManifest ||
          state is CreateManifestCheckingForConflicts) {
        return ProgressDialog(title: l10n.deploymentPreparing);
      } else if (state is CreateManifestNameConflict) {
        return _createManifestNameConflict(context, state);
      } else if (state is CreateManifestRevisionConfirm) {
        return _createManifestRevisionConfirm(context);
      } else if (state is CreateManifestInitial) {
        return ProgressDialog(title: l10n.loadingFolders);
      } else if (state is CreateManifestUploadInProgress) {
        return ProgressDialog(
          title: l10n.deploymentCreating,
          progressDescription: Text(
            _getProgressDescription(context, state.progress),
            style: typography.paragraphLarge(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
        );
      } else if (state is CreateManifestUploadReview) {
        return _createManifestUploadReview(state: state, context: context);
      } else if (state is CreateManifestFolderLoadSuccess) {
        return _selectFolder(state, context);
      }

      return const SizedBox();
    });
  }

  /// A failure stays in the dialog, in a notice, with the way on: Try again
  /// where a retry sends the same deployment again, and Buy credits when
  /// Turbo wants credits. A wallet that changed has nothing to retry.
  Widget _failureModal(BuildContext context, CreateManifestState state) {
    final l10n = appLocalizationsOf(context);
    final isPaymentError =
        state is CreateManifestFailure && state.isPaymentError;
    final isWalletMismatch = state is CreateManifestWalletMismatch;
    final postedTxId = state is CreateManifestFailure ? state.postedTxId : null;
    final canRetry = state is CreateManifestFailure && state.canRetry;

    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: isPaymentError
          ? l10n.freeAllowanceUsedUpTitle
          : l10n.deploymentFailedTitle,
      content: ArDriveNotice(
        type: ArDriveNoticeType.error,
        message: postedTxId != null
            ? l10n.deploymentPostedBody(postedTxId)
            : isPaymentError
                ? l10n.freeAllowanceUsedUpDescription
                : isWalletMismatch
                    ? l10n.deploymentWalletChanged
                    : l10n.deploymentFailedBody,
      ),
      actions: [
        ModalAction.close(
          isEnable: !_submitting,
          action: () => Navigator.pop(context),
          title: l10n.close,
        ),
        if (isPaymentError)
          ModalAction(
            action: () {
              Navigator.pop(context);
              showTurboTopupModal(context);
            },
            title: l10n.buyCredits,
          )
        else if (!isWalletMismatch && canRetry)
          ModalAction(
            isLoading: _submitting,
            action: () => _submit(
              () => context.read<CreateManifestCubit>().retryUpload(),
            ),
            title: l10n.tryAgain,
          ),
      ],
    );
  }

  Widget _createManifestSuccess(
    BuildContext context,
    CreateManifestSuccess state, {
    ArNSFlowOutcome? names,
    bool nameFailed = false,
  }) {
    final l10n = appLocalizationsOf(context);
    void finish() {
      context
          .read<DriveDetailCubit>()
          .openFolder(folderId: state.parentFolder.id);
      context.read<DriveDetailCubit>().refreshDriveDataTable();
      Navigator.pop(context);
    }

    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: l10n.deploymentCreatedTitle,
      content: nameFailed
          ? ArDriveNotice(
              type: ArDriveNoticeType.warning,
              message: l10n.deploymentNameNotSet,
            )
          : names != null && !names.isEmpty
              ? ArNSFlowNameResult(outcome: names)
              : null,
      actions: [
        ModalAction.close(
          action: finish,
          title: l10n.close,
        ),
      ],
    );
  }

  String _getProgressDescription(
    BuildContext context,
    CreateManifestUploadProgress progress,
  ) {
    final l10n = appLocalizationsOf(context);
    switch (progress) {
      case CreateManifestUploadProgress.preparingManifest:
        return l10n.deploymentPreparing;
      case CreateManifestUploadProgress.uploadingManifest:
        return l10n.deploymentUploading;
      case CreateManifestUploadProgress.completed:
        return l10n.doneEmphasized;
    }
  }

  bool _isFolderEmpty(FolderID folderId, FolderNode rootFolderNode) {
    final folderNode = rootFolderNode.searchForFolder(folderId);

    if (folderNode == null) {
      return true;
    }

    return folderNode.isEmpty();
  }

  /// A file or folder already has the name: asked for another, in the
  /// dialog, with that said in words of its own.
  Widget _createManifestNameConflict(
    BuildContext context,
    CreateManifestNameConflict state,
  ) {
    final l10n = appLocalizationsOf(context);
    final cubit = context.read<CreateManifestCubit>();
    final canRetry =
        _isFormValid && _manifestNameController.text != state.conflictingName;

    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: l10n.deploymentNameConflictTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message: l10n.deploymentNameConflictBody(state.conflictingName),
          ),
          const SizedBox(height: ArDriveSpacing.md),
          manifestNameForm(
            onSubmit: (name) {
              if (canRetry) _submit(() => cubit.reCheckConflicts(name));
            },
          ),
        ],
      ),
      actions: [
        ModalAction.close(
          isEnable: !_submitting,
          action: () => Navigator.of(context).pop(false),
          title: l10n.cancelEmphasized,
        ),
        ModalAction(
          isEnable: canRetry,
          isLoading: _submitting,
          action: () => _submit(
            () => cubit.reCheckConflicts(_manifestNameController.text),
          ),
          title: l10n.deploymentUseName,
        ),
      ],
    );
  }

  /// A deployment of that name is already here: say so, and that creating
  /// this one adds a version of it.
  Widget _createManifestRevisionConfirm(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final cubit = context.read<CreateManifestCubit>();
    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: l10n.deploymentExistsTitle,
      description: l10n.deploymentExistsBody(_manifestNameController.text),
      actions: [
        ModalAction.close(
          isEnable: !_submitting,
          action: () => Navigator.of(context).pop(false),
          title: l10n.cancelEmphasized,
        ),
        ModalAction(
          isLoading: _submitting,
          action: () => _submit(
            () => cubit.confirmRevision(_manifestNameController.text),
          ),
          title: l10n.deploymentCreateNewVersion,
        ),
      ],
    );
  }

  Widget _createManifestUploadReview({
    required CreateManifestUploadReview state,
    required BuildContext context,
  }) {
    final names = _nameStep(state);
    if (names != null) {
      return BlocBuilder<ArNSNameDialogCubit, ArNSNameDialogState>(
        bloc: names,
        builder: (context, _) => BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
          builder: (context, __) => _reviewModal(
            state: state,
            context: context,
            names: names,
          ),
        ),
      );
    }
    return _reviewModal(state: state, context: context);
  }

  Widget _reviewModal({
    required CreateManifestUploadReview state,
    required BuildContext context,
    ArNSFlowNameCubit? names,
  }) {
    final l10n = appLocalizationsOf(context);
    final readCubitContext = context.read<CreateManifestCubit>();
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final hasPendingFiles = state.folderHasPendingFiles;
    final textStyle = typography.paragraphNormal(color: colorTokens.textMid);

    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      // The name step makes this taller than a laptop screen: without a
      // scroll, Create deployment was pushed below the window.
      scrollableContent: true,
      title: l10n.createManifestEmphasized,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPendingFiles) ...[
            ArDriveNotice(
              type: ArDriveNoticeType.warning,
              message: l10n.filesPendingManifestExplanation,
            ),
            const SizedBox(height: ArDriveSpacing.md),
          ],
          Text(
            state.manifestName,
            style: typography.paragraphLarge(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
          Text(filesize(state.manifestSize), style: textStyle),
          if (state.fallbackTxId != null) ...[
            const SizedBox(height: ArDriveSpacing.xs),
            RichText(
              text: TextSpan(
                style: textStyle,
                children: [
                  TextSpan(
                    text: '${l10n.manifestFallbackTxID}\n',
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
          const SizedBox(height: ArDriveSpacing.lg),
          TurboFreeStatusMessage(
            status: state.freeStatus,
            padding: const EdgeInsets.only(bottom: ArDriveSpacing.lg),
          ),
          if (!state.freeUpload) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: ArDriveSpacing.lg),
              child: _paymentOptions(state, context),
            ),
          ],
          if (names != null) ...[
            ArNSFlowNameSection(cubit: names),
            const SizedBox(height: ArDriveSpacing.lg),
          ],
          Text(l10n.filesWillBePermanentlyPublicWarning, style: textStyle),
        ],
      ),
      actions: [
        ModalAction.close(
          isEnable: !_submitting,
          action: () => Navigator.of(context).pop(false),
          title: l10n.cancelEmphasized,
        ),
        ModalAction(
          isEnable: state.canUpload && (names?.ready ?? true),
          isLoading: _submitting,
          action: () => _submit(() => readCubitContext.uploadManifest()),
          title: l10n.createManifestEmphasized,
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

  /// The folder to deploy, the deployment's name and, if wanted, its
  /// fallback page: one screen, then the review with the cost.
  Widget _selectFolder(
      CreateManifestFolderLoadSuccess state, BuildContext context) {
    final cubit = context.read<CreateManifestCubit>();
    final l10n = appLocalizationsOf(context);

    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final rowStyle = typography.paragraphLarge(
      fontWeight: ArFontWeight.bold,
      color: colorTokens.textHigh,
    );
    final disabledStyle = typography.paragraphLarge(
      color: colorTokens.iconLow,
    );

    final items = <Widget>[
      ...state.viewingFolder.subfolders
          .where((element) => !element.isHidden)
          .map(
        (f) {
          final enabled = !_isFolderEmpty(f.id, cubit.rootFolderNode);

          return ArDriveClickArea(
            showCursor: enabled,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => cubit.loadFolder(f.id) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: ArDriveSpacing.sm,
                  horizontal: ArDriveSpacing.md,
                ),
                child: Row(
                  children: [
                    ArDriveIcons.folderOutline(
                      size: 20,
                      color:
                          enabled ? colorTokens.textHigh : colorTokens.iconLow,
                    ),
                    const SizedBox(width: ArDriveSpacing.xs),
                    Expanded(
                      child: Text(
                        f.name,
                        style: enabled ? rowStyle : disabledStyle,
                      ),
                    ),
                    ArDriveIcons.carretRight(
                      size: 24,
                      color:
                          enabled ? colorTokens.textHigh : colorTokens.iconLow,
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
                vertical: ArDriveSpacing.sm,
                horizontal: ArDriveSpacing.md,
              ),
              child: Row(
                children: [
                  ArDriveIcons.file(size: 20, color: colorTokens.iconLow),
                  const SizedBox(width: ArDriveSpacing.xs),
                  Expanded(child: Text(f.name, style: disabledStyle)),
                ],
              ),
            ),
          ),
    ];

    final canContinue = state.enableManifestCreationButton && _isFormValid;

    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      scrollableContent: true,
      title: l10n.addnewManifestEmphasized,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(children: [
              TextSpan(
                text: l10n.aManifestIsASpecialKindOfFile,
                style: typography.paragraphNormal(color: colorTokens.textMid),
              ),
              const TextSpan(text: ' '),
              ArDriveLink.span(
                text: l10n.learnMore,
                style: typography.paragraphNormal(color: colorTokens.textMid),
                color: colorTokens.textMid,
                external: true,
                onTap: () => openUrl(url: Resources.manifestLearnMoreLink),
              ),
            ]),
          ),
          const SizedBox(height: ArDriveSpacing.lg),
          manifestNameForm(
            onSubmit: (name) {
              if (state.enableManifestCreationButton) {
                _submit(() => cubit.checkForConflicts(name));
              }
            },
          ),
          const SizedBox(height: ArDriveSpacing.lg),
          Text(
            l10n.deploymentFolder,
            style: typography.paragraphNormal(
              color: colorTokens.textLow,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: ArDriveSpacing.xs),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: colorTokens.strokeLow),
              borderRadius: BorderRadius.circular(ArDriveRadius.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: colorTokens.containerL1,
                  padding: const EdgeInsets.symmetric(
                    horizontal: ArDriveSpacing.md,
                    vertical: ArDriveSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      if (!state.viewingRootFolder)
                        Semantics(
                          button: true,
                          label: l10n.back,
                          excludeSemantics: true,
                          child: ArDriveClickArea(
                            child: GestureDetector(
                              onTap: cubit.loadParentFolder,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: ArDriveSpacing.xs,
                                ),
                                child: ArDriveIcons.arrowLeft(size: 20),
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          state.viewingFolder.folder.name,
                          overflow: TextOverflow.ellipsis,
                          style: typography.paragraphLarge(
                            color: colorTokens.textHigh,
                            fontWeight: ArFontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // The one list that scrolls on its own: a folder can hold
                // hundreds of entries, and the name and the fallback page
                // stay in reach.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: items,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ArDriveSpacing.lg),
          ArDriveTextFieldNew(
            label: l10n.deploymentFallbackLabel,
            textStyle: typography.code(),
            isEnabled: !_submitting,
            onChanged: (value) {
              cubit.setFallbackTxId(value);
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return null;
              }

              return isValidArweaveTxId(value)
                  ? null
                  : l10n.deploymentInvalidTxId;
            },
          ),
          const SizedBox(height: ArDriveSpacing.xs),
          Text(
            l10n.deploymentFallbackHelp,
            style: typography.paragraphSmall(color: colorTokens.textMid),
          ),
          const SizedBox(height: ArDriveSpacing.lg),
          ArDriveNotice(
            type: ArDriveNoticeType.info,
            message: l10n.deploymentHiddenNotice,
          ),
        ],
      ),
      actions: [
        ModalAction.close(
          isEnable: !_submitting,
          action: () => Navigator.pop(context),
          title: l10n.cancelEmphasized,
        ),
        ModalAction(
          isEnable: canContinue,
          isLoading: _submitting,
          action: () => _submit(
            () => cubit.checkForConflicts(_manifestNameController.text),
          ),
          title: l10n.review,
        ),
      ],
    );
  }
}

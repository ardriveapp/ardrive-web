import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/blocs/markdown/upload_markdown_cubit.dart';
import 'package:ardrive/blocs/markdown/upload_markdown_state.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/blocs/upload/payment_method/view/upload_payment_method_view.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/markdown/domain/markdown_repository.dart';
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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pst/pst.dart';

import '../utils/show_general_dialog.dart';
import 'components.dart';

Future<void> promptToUploadMarkdown(
  BuildContext context, {
  required Drive drive,
  required String markdownText,
  required FolderEntry parentFolderEntry,
}) {
  final pst = context.read<PstService>();
  final configService = context.read<ConfigService>();
  return showArDriveDialog(
    context,
    content: BlocProvider(
      create: (context) => UploadMarkdownCubit(
        drive: drive,
        profileCubit: context.read<ProfileCubit>(),
        auth: context.read<ArDriveAuth>(),
        markdownRepository: MarkdownRepositoryImpl(
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
        ),
        markdownText: markdownText,
        parentFolderEntry: parentFolderEntry,
      ),
      child: const UploadMarkdownForm(),
    ),
  );
}

class UploadMarkdownForm extends StatefulWidget {
  const UploadMarkdownForm({super.key});

  @override
  State<UploadMarkdownForm> createState() => _UploadMarkdownFormState();
}

class _UploadMarkdownFormState extends State<UploadMarkdownForm> {
  final _markdownNameController = TextEditingController();

  bool _isFormValid = false;

  ArDriveTextFieldNew markdownNameForm() {
    final readCubitContext = context.read<UploadMarkdownCubit>();

    return ArDriveTextFieldNew(
      hintText: appLocalizationsOf(context).enterFileName,
      controller: _markdownNameController,
      validator: (value) {
        final validation = validateEntityName(value, context);

        _isFormValid = validation == null;

        setState(() {});

        return validation;
      },
      autofocus: true,
      onFieldSubmitted: (s) {
        readCubitContext.checkForConflicts(_markdownNameController.text);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocConsumer<UploadMarkdownCubit, UploadMarkdownState>(
        listener: (context, state) {
      if (state is UploadMarkdownSuccess ||
          state is UploadMarkdownPrivacyMismatch) {
        Navigator.pop(context);
        context.read<FeedbackSurveyCubit>().openRemindMe();
      }
    }, builder: (context, state) {
      final textStyle = typography.paragraphNormal(
        color: colorTokens.textLow,
        fontWeight: ArFontWeight.semiBold,
      );

      ArDriveStandardModal errorDialog({required String errorText}) =>
          ArDriveStandardModal(
            width: kMediumDialogWidth,
            title: appLocalizationsOf(context).failed,
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

      if (state is UploadMarkdownWalletMismatch) {
        Navigator.pop(context);
        return errorDialog(
          errorText: appLocalizationsOf(context).walletChangeDetected,
        );
      } else if (state is UploadMarkdownFailure) {
        Navigator.pop(context);
        return errorDialog(
          errorText: appLocalizationsOf(context).uploadFailed,
        );
      } else if (state is UploadMarkdownPreparingFile) {
        return ProgressDialog(
          useNewArDriveUI: true,
          title: appLocalizationsOf(context).preparingUpload,
        );
      } else if (state is UploadMarkdownNameConflict) {
        return _uploadMarkdownNameConflict(
          contexty: context,
          textStyle: textStyle,
        );
      } else if (state is UploadMarkdownRevisionConfirm) {
        return _uploadMarkdownRevisionConfirm(
          context: context,
          textStyle: textStyle,
        );
      } else if (state is UploadMarkdownInitial) {
        return _uploadMarkdownInitial(
          context: context,
          textStyle: textStyle,
        );
      }
      if (state is MarkdownUploadInProgress) {
        return ProgressDialog(
          useNewArDriveUI: true,
          title: appLocalizationsOf(context).uploadingNFiles(1),
        );
      } else if (state is MarkdownUploadReview) {
        return _uploadMarkdownUploadReview(
          state: state,
          context: context,
          textStyle: textStyle,
        );
      }

      return const SizedBox();
    });
  }

  bool _isFolderEmpty(FolderID folderId, FolderNode rootFolderNode) {
    final folderNode = rootFolderNode.searchForFolder(folderId);

    if (folderNode == null) {
      return true;
    }

    return folderNode.isEmpty();
  }

  Widget _uploadMarkdownNameConflict({
    required BuildContext contexty,
    required TextStyle textStyle,
  }) {
    final readCubitContext = context.read<UploadMarkdownCubit>();

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
              appLocalizationsOf(context).conflictingNameFoundChooseNewName,
              style: textStyle,
            ),
            markdownNameForm()
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
              readCubitContext.recheckConflicts(_markdownNameController.text),
          title: appLocalizationsOf(context).continueEmphasized,
        ),
      ],
    );
  }

  Widget _uploadMarkdownRevisionConfirm({
    required BuildContext context,
    required TextStyle textStyle,
  }) {
    final readCubitContext = context.read<UploadMarkdownCubit>();
    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: appLocalizationsOf(context).conflictingNameFound,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            appLocalizationsOf(context).conflictingNameFoundChooseNewName,
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
              readCubitContext.confirmRevision(_markdownNameController.text),
          title: appLocalizationsOf(context).continueEmphasized,
        ),
      ],
    );
  }

  Widget _uploadMarkdownInitial({
    required BuildContext context,
    required TextStyle textStyle,
  }) {
    final readCubitContext = context.read<UploadMarkdownCubit>();
    return ArDriveStandardModalNew(
      width: kLargeDialogWidth,
      title:
          appLocalizationsOf(context).addnewManifestEmphasized, // TODO: UPDATE
      actions: [
        ModalAction(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).cancelEmphasized,
        ),
        ModalAction(
          isEnable: _isFormValid,
          action: () =>
              readCubitContext.checkForConflicts(_markdownNameController.text),
          title: appLocalizationsOf(context).nextEmphasized,
        ),
      ],
      content: SizedBox(
        height: 250,
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
                        .aManifestIsASpecialKindOfFile, // trimmed spaces // TODO: EXCISE
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
                            url:
                                Resources.manifestLearnMoreLink, // TODO: EXCISE
                          ),
                  ),
                ]),
              ),
              markdownNameForm()
            ],
          ),
        ),
      ),
    );
  }

  Widget _uploadMarkdownUploadReview({
    required MarkdownUploadReview state,
    required BuildContext context,
    required TextStyle textStyle,
  }) {
    final readCubitContext = context.read<UploadMarkdownCubit>();
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ArDriveStandardModalNew(
      width: kMediumDialogWidth,
      title: appLocalizationsOf(context).uploadEmphasized,
      content: SizedBox(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 256),
              child: Scrollbar(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        state.markdownName,
                        style: typography.paragraphLarge(
                          color: colorTokens.textHigh,
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        filesize(state.markdownSize),
                        style: textStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            const SizedBox(height: 16),
            if (state.freeUpload) ...[
              Text(
                appLocalizationsOf(context).freeTurboTransaction,
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                  fontWeight: ArFontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (!state.freeUpload) ...[
              MultiBlocProvider(
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
                            wallet:
                                context.read<ArDriveAuth>().currentUser.wallet,
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
                          turboUploadService:
                              context.read<TurboUploadService>(),
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
                                ioFile: state.markdownFile,
                                parentFolderId: state.parentFolderEntry.id,
                              ),
                            ],
                            foldersByPath:
                                UploadPlanUtils.generateFoldersForFiles([
                              UploadFile(
                                ioFile: state.markdownFile,
                                parentFolderId: state.parentFolderEntry.id,
                              ),
                            ]),
                            targetDrive: state.drive,
                            targetFolder: state.parentFolderEntry,
                            user: context.read<ArDriveAuth>().currentUser,
                            // Theres no thumbnail generation for markdown files
                            containsSupportedImageTypeForThumbnailGeneration:
                                false,
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
                          padding: EdgeInsets.symmetric(
                              vertical: 8.0, horizontal: 32),
                          child: SizedBox(
                            child: LinearProgressIndicator(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  useNewArDriveUI: true,
                ),
              ),
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
          isEnable: state.canUpload,
          action: () => readCubitContext.uploadMarkdown(),
          title: appLocalizationsOf(context).confirmEmphasized,
        ),
      ],
    );
  }

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colorTokens.iconLow;
}

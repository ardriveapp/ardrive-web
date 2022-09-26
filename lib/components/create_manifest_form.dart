import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToCreateManifest(BuildContext context,
    {required Drive drive}) {
  return showDialog(
    context: context,
    builder: (_) => BlocProvider(
      create: (context) => CreateManifestCubit(
          drive: drive,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          pst: context.read<PstService>()),
      child: const CreateManifestForm(),
    ),
  );
}

class CreateManifestForm extends StatelessWidget {
  const CreateManifestForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<CreateManifestCubit, CreateManifestState>(
          listener: (context, state) {
        if (state is CreateManifestUploadInProgress) {
          showProgressDialog(
            context,
            appLocalizationsOf(context).uploadingManifestEmphasized,
          );
        } else if (state is CreateManifestPreparingManifest) {
          showProgressDialog(
            context,
            appLocalizationsOf(context).preparingManifestEmphasized,
          );
        } else if (state is CreateManifestSuccess ||
            state is CreateManifestPrivacyMismatch) {
          Navigator.pop(context);
          Navigator.pop(context);
          context.read<FeedbackSurveyCubit>().openRemindMe();
        }
      }, builder: (context, state) {
        final readCubitContext = context.read<CreateManifestCubit>();

        ReactiveForm manifestNameForm() => ReactiveForm(
            formGroup: context.watch<CreateManifestCubit>().form,
            child: ReactiveTextField(
              formControlName: 'name',
              autofocus: true,
              decoration: InputDecoration(
                labelText: appLocalizationsOf(context).manifestName,
              ),
              showErrors: (control) => control.dirty && control.invalid,
              validationMessages:
                  kValidationMessages(appLocalizationsOf(context)),
            ));

        AppDialog errorDialog({required String errorText}) => AppDialog(
              title:
                  appLocalizationsOf(context).failedToCreateManifestEmphasized,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(errorText),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              actions: <Widget>[
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(appLocalizationsOf(context).continueEmphasized),
                ),
              ],
            );

        if (state is CreateManifestWalletMismatch) {
          Navigator.pop(context);
          return errorDialog(
            errorText:
                appLocalizationsOf(context).walletChangedDuringManifestCreation,
          );
        }

        if (state is CreateManifestFailure) {
          Navigator.pop(context);
          return errorDialog(
            errorText: appLocalizationsOf(context)
                .manifestTransactionUnexpectedlyFailed,
          );
        }

        if (state is CreateManifestInsufficientBalance) {
          Navigator.pop(context);
          return errorDialog(
            errorText: appLocalizationsOf(context)
                .insufficientBalanceForManifest(
                    state.walletBalance, state.totalCost),
          );
        }

        if (state is CreateManifestNameConflict) {
          return AppDialog(
            title: appLocalizationsOf(context).conflictingNameFound,
            content: SizedBox(
              width: kMediumDialogWidth,
              height: 200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    appLocalizationsOf(context)
                        .conflictingManifestFoundChooseNewName,
                  ),
                  manifestNameForm()
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(appLocalizationsOf(context).cancelEmphasized),
              ),
              ElevatedButton(
                onPressed: () => readCubitContext.reCheckConflicts(),
                child: Text(appLocalizationsOf(context).continueEmphasized),
              ),
            ],
          );
        }

        if (state is CreateManifestRevisionConfirm) {
          return AppDialog(
            title: appLocalizationsOf(context).conflictingManifestFound,
            content: SizedBox(
              width: kMediumDialogWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    appLocalizationsOf(context)
                        .conflictingManifestFoundChooseNewName,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(appLocalizationsOf(context).cancelEmphasized),
              ),
              ElevatedButton(
                onPressed: () => readCubitContext.confirmRevision(),
                child: Text(appLocalizationsOf(context).continueEmphasized),
              ),
            ],
          );
        }

        if (state is CreateManifestInitial) {
          return AppDialog(
              title: appLocalizationsOf(context).addnewManifestEmphasized,
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(appLocalizationsOf(context).cancelEmphasized)),
                ElevatedButton(
                  onPressed: () => readCubitContext.chooseTargetFolder(),
                  child: Text(
                    appLocalizationsOf(context).nextEmphasized,
                  ),
                ),
              ],
              content: SizedBox(
                width: kLargeDialogWidth,
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
                                    .aManifestIsASpecialKindOfFile, // trimmed spaces
                                style: Theme.of(context).textTheme.bodyText1),
                            TextSpan(
                              text: appLocalizationsOf(context).learnMore,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyText1
                                      ?.color,
                                  fontSize: Theme.of(context)
                                      .textTheme
                                      .bodyText1
                                      ?.fontSize,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => openUrl(
                                      url: Resources.manifestLearnMoreLink,
                                    ),
                            ),
                          ]),
                        ),
                        manifestNameForm()
                      ],
                    )),
              ));
        }

        if (state is CreateManifestUploadConfirmation) {
          Navigator.pop(context);
          return AppDialog(
            title: appLocalizationsOf(context).createManifestEmphasized,
            content: SizedBox(
              width: kMediumDialogWidth,
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
                            title: Text(state.manifestName),
                            subtitle: Text(filesize(state.manifestSize)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: appLocalizationsOf(context)
                              .cost(state.arUploadCost),
                        ),
                        TextSpan(
                            text: state.usdUploadCost >= 0.01
                                ? ' (~${state.usdUploadCost.toStringAsFixed(2)} USD)'
                                : ' (< 0.01 USD)'),
                      ],
                      style: Theme.of(context).textTheme.bodyText1,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    appLocalizationsOf(context)
                        .filesWillBePermanentlyPublicWarning,
                    style: Theme.of(context).textTheme.bodyText2,
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(appLocalizationsOf(context).cancelEmphasized),
              ),
              ElevatedButton(
                onPressed: () => readCubitContext.uploadManifest(),
                child: Text(appLocalizationsOf(context).confirmEmphasized),
              ),
            ],
          );
        }

        if (state is CreateManifestFolderLoadSuccess) {
          return AppDialog(
            title: appLocalizationsOf(context).createManifestEmphasized,
            actions: [
              TextButton(
                onPressed: () => readCubitContext.backToName(),
                child: Text(appLocalizationsOf(context).backEmphasized),
              ),
              ElevatedButton(
                onPressed: () => readCubitContext.checkForConflicts(),
                child: Text(appLocalizationsOf(context).createHereEmphasized),
              ),
            ],
            content: SizedBox(
                width: kLargeDialogWidth,
                height: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(appLocalizationsOf(context).targetFolderEmphasized),
                    if (!state.viewingRootFolder)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            textStyle: Theme.of(context).textTheme.subtitle2,
                            padding: const EdgeInsets.all(16),
                          ),
                          onPressed: () => readCubitContext.loadParentFolder(),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.arrow_back),
                            title: Text(appLocalizationsOf(context).back),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Scrollbar(
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              ...state.viewingFolder.subfolders.map(
                                (f) => ListTile(
                                  key: ValueKey(f.id),
                                  dense: true,
                                  leading: const Icon(Icons.folder),
                                  title: Text(f.name),
                                  onTap: () =>
                                      readCubitContext.loadFolder(f.id),
                                  trailing:
                                      const Icon(Icons.keyboard_arrow_right),
                                  enabled: !_isFolderEmpty(
                                    f.id,
                                    readCubitContext.rootFolderNode,
                                  ),
                                ),
                              ),
                              ...state.viewingFolder.files
                                  .where((f) =>
                                      // New manifests will not include existing manifests
                                      // So we will not display them to the user by filtering them out
                                      f.dataContentType != ContentType.manifest)
                                  .map(
                                    (f) => ListTile(
                                      key: ValueKey(f.id),
                                      leading:
                                          const Icon(Icons.insert_drive_file),
                                      title: Text(f.name),
                                      enabled: false,
                                      dense: true,
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                )),
          );
        }
        return const SizedBox();
      });

  bool _isFolderEmpty(FolderID folderId, FolderNode rootFolderNode) {
    final folderNode = rootFolderNode.searchForFolder(folderId);

    if (folderNode == null) {
      return true;
    }

    return folderNode.isEmpty();
  }
}

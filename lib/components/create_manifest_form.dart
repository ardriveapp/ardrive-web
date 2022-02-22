import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:url_launcher/url_launcher.dart';

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
      child: CreateManifestForm(),
    ),
  );
}

class CreateManifestForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<CreateManifestCubit, CreateManifestState>(
          listener: (context, state) {
        if (state is CreateManifestUploadInProgress) {
          showProgressDialog(context, 'UPLOADING MANIFEST...');
        } else if (state is CreateManifestSuccess ||
            state is CreateManifestWalletMismatch ||
            state is CreateManifestFailure ||
            state is CreateManifestPrivacyMismatch) {
          Navigator.pop(context);
          Navigator.pop(context);
        }
      }, builder: (context, state) {
        final readCubitContext = context.read<CreateManifestCubit>();

        ReactiveForm manifestNameForm() => ReactiveForm(
            formGroup: context.watch<CreateManifestCubit>().form,
            child: ReactiveTextField(
              formControlName: 'name',
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Manifest name'),
              showErrors: (control) => control.dirty && control.invalid,
              validationMessages: (_) => kValidationMessages,
            ));

        if (state is CreateManifestNameConflict) {
          return AppDialog(
            title: 'Conflicting name was found',
            content: SizedBox(
              width: kMediumDialogWidth,
              height: 200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                      'An entity with that name already exists at this location. Please choose a new name.'),
                  manifestNameForm()
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () => readCubitContext.form.invalid
                    ? null
                    : readCubitContext.checkForConflicts(
                        parentFolder: state.parentFolder),
                child: Text('CONTINUE'),
              ),
            ],
          );
        }

        if (state is CreateManifestRevisionConfirm) {
          return AppDialog(
            title: 'Conflicting manifest was found',
            content: SizedBox(
              width: kMediumDialogWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16),
                  Text(
                      'A manifest with the same name already exists at this location. Do you want to continue and upload this manifest as a new version?'),
                  SizedBox(height: 16),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () => readCubitContext.uploadManifest(
                    existingManifestFileId: state.id,
                    parentFolder: state.parentFolder),
                child: Text('CONTINUE'),
              ),
            ],
          );
        }

        if (state is CreateManifestInitial) {
          return AppDialog(
              title: 'ADD NEW MANIFEST',
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('CANCEL')),
                ElevatedButton(
                  onPressed: () => readCubitContext.form.invalid
                      ? null
                      : readCubitContext
                          .loadFolder(readCubitContext.drive.rootFolderId),
                  child: Text('NEXT'),
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
                                text:
                                    'A manifest is a special kind of file that maps any number of Arweave transactions to friendly path names.  ',
                                style: Theme.of(context).textTheme.bodyText1),
                            TextSpan(
                                text: 'Learn More',
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
                                  ..onTap =
                                      () => launch(R.manifestLearnMoreLink)),
                          ]),
                        ),
                        manifestNameForm()
                      ],
                    )),
              ));
        }

        if (state is CreateManifestFolderLoadSuccess) {
          return AppDialog(
            title: 'CREATE MANIFEST',
            actions: [
              TextButton(
                  onPressed: () => readCubitContext.backToName(),
                  child: Text('BACK')),
              ElevatedButton(
                onPressed: () => readCubitContext.checkForConflicts(
                    parentFolder: state.viewingFolder.folder),
                child: Text('CREATE'),
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
                    Text('TARGET FOLDER'),
                    if (!state.viewingRootFolder)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextButton(
                            style: TextButton.styleFrom(
                                textStyle:
                                    Theme.of(context).textTheme.subtitle2,
                                padding: const EdgeInsets.all(16)),
                            onPressed: () =>
                                readCubitContext.loadParentFolder(),
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.arrow_back),
                              title: Text('Back'),
                            )),
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
                                  trailing: Icon(Icons.keyboard_arrow_right),
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
                                      leading: Icon(Icons.insert_drive_file),
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
        return SizedBox();
      });
}

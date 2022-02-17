import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToCreateManifest(BuildContext context,
    {required DriveID driveId}) {
  return showDialog(
    context: context,
    builder: (_) => BlocProvider(
      create: (context) => CreateManifestCubit(
          driveId: driveId,
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
            // TODO: Handle name conflict state instead of exiting AppDialog
            state is CreateManifestNameConflict) {
          Navigator.pop(context);
          Navigator.pop(context);
        }
      }, builder: (context, state) {
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
                onPressed: () => context
                    .read<CreateManifestCubit>()
                    .uploadManifest(
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
                  onPressed: () =>
                      context.read<CreateManifestCubit>().chooseFolder(),
                  child: Text('NEXT'),
                ),
              ],
              content: SizedBox(
                width: kMediumDialogWidth,
                height: 250,
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'A manifest is a special kind of file that maps any number of Arweave transactions to friendly path names. (Learn More): TODO LINK',
                        ),
                        ReactiveForm(
                            formGroup:
                                context.watch<CreateManifestCubit>().form,
                            child: ReactiveTextField(
                              formControlName: 'name',
                              autofocus: true,
                              decoration: const InputDecoration(
                                  labelText: 'Manifest name'),
                              showErrors: (control) =>
                                  control.dirty && control.invalid,
                              validationMessages: (_) => kValidationMessages,
                            )),
                      ],
                    )),
              ));
        }

        if (state is CreateManifestFolderLoadSuccess) {
          return AppDialog(
            title: 'CREATE MANIFEST',
            actions: [
              TextButton(
                  onPressed: () =>
                      context.read<CreateManifestCubit>().backToName(),
                  child: Text('BACK')),
              ElevatedButton(
                onPressed: () =>
                    context.read<CreateManifestCubit>().checkForConflicts(),
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
                            onPressed: () => context
                                .read<CreateManifestCubit>()
                                .loadParentFolder(),
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
                                  onTap: () => context
                                      .read<CreateManifestCubit>()
                                      .loadFolder(f.id),
                                  trailing: Icon(Icons.keyboard_arrow_right),
                                  // Do not allow users to navigate into the folder they are currently trying to move.
                                  enabled: f.id != state.movingEntryId,
                                ),
                              ),
                              ...state.viewingFolder.files.map(
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

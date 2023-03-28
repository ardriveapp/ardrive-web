import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lottie/lottie.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../components/details_panel.dart';
import '../drive_detail/components/drive_explorer_item_tile.dart';

/// [SharedFilePage] displays details of a shared file and controls for downloading and previewing it
/// from a parent [SharedFileCubit].
class SharedFilePage extends StatelessWidget {
  const SharedFilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      child: BlocBuilder<SharedFileCubit, SharedFileState>(
        builder: (context, state) {
          Widget shareCard() {
            return ArDriveCard(
              backgroundColor:
                  ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
              elevation: 2,
              content: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kMediumDialogWidth,
                      minWidth: kMediumDialogWidth,
                      minHeight: 256,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Lottie.asset(
                              'assets/animations/lottie.json',
                              width: 100,
                              height: 100,
                              fit: BoxFit.fill,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'ardrive',
                              style: ArDriveTypography.headline
                                  .heroBold()
                                  .copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                            )
                          ],
                        ),
                        const SizedBox(height: 32),
                        if (state is SharedFileIsPrivate) ...[
                          Text(appLocalizationsOf(context)
                              .sharedFileIsEncrypted),
                          const SizedBox(height: 16),
                          ReactiveForm(
                            formGroup: context.watch<SharedFileCubit>().form,
                            child: ReactiveTextField(
                              formControlName: 'fileKey',
                              autofocus: true,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText:
                                    appLocalizationsOf(context).enterFileKey,
                              ),
                              validationMessages: kValidationMessages(
                                  appLocalizationsOf(context)),
                              onEditingComplete: (_) => context
                                  .read<SharedFileCubit>()
                                  .form
                                  .updateValueAndValidity(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () =>
                                context.read<SharedFileCubit>().submit(),
                            child: Text(appLocalizationsOf(context).unlock),
                          ),
                        ],
                        if (state is SharedFileLoadInProgress)
                          const CircularProgressIndicator()
                        else if (state is SharedFileLoadSuccess) ...{
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: DriveExplorerItemTileLeading(
                              item: DriveDataTableItemMapper.fromRevision(
                                state.fileRevisions.first,
                              ),
                            ),
                            title: Text(
                              state.fileRevisions.first.name,
                              style: ArDriveTypography.body.buttonLargeBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgDefault,
                              ),
                            ),
                            subtitle: Text(
                              filesize(state.fileRevisions.first.size),
                              style: ArDriveTypography.body.buttonNormalRegular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeAccentDisabled,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ArDriveButton(
                            icon: ArDriveIcons.download(),
                            onPressed: () {
                              final file =
                                  ARFSFactory().getARFSFileFromFileRevision(
                                state.fileRevisions.first,
                              );
                              return promptToDownloadSharedFile(
                                revision: file,
                                context: context,
                                fileKey: state.fileKey,
                              );
                            },
                            text: appLocalizationsOf(context).download,
                          ),
                          const SizedBox(height: 16),
                          _buildReturnToAppLink(context),
                        } else if (state is SharedFileNotFound) ...{
                          const Icon(Icons.error_outline, size: 36),
                          const SizedBox(height: 16),
                          Text(
                            appLocalizationsOf(context)
                                .specifiedFileDoesNotExist,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          _buildReturnToAppLink(context),
                        }
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          Widget activityPanel(SharedFileLoadSuccess state) {
            return DetailsPanel(
              item: DriveDataTableItemMapper.fromRevision(
                state.fileRevisions.first,
              ),
              isSharePage: true,
              maybeSelectedItem: null,
              fileKey: state.fileKey,
              revisions: state.fileRevisions,
              drivePrivacy: state.fileKey != null ? 'private' : 'public',
            );
          }

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: ScreenTypeLayout(
              desktop: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    flex: 2,
                    child: shareCard(),
                  ),
                  if (state is SharedFileLoadSuccess) ...{
                    Flexible(
                      flex: 1,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 24.0),
                        child: activityPanel(state),
                      ),
                    )
                  }
                ],
              ),
              mobile: ListView(
                children: [
                  shareCard(),
                  const SizedBox(
                    height: 16,
                  ),
                  if (state is SharedFileLoadSuccess) ...{
                    activityPanel(state),
                  }
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReturnToAppLink(BuildContext context) {
    return ArDriveButton(
      style: ArDriveButtonStyle.tertiary,
      onPressed: () => openUrl(url: 'https://ardrive.io/'),
      text: appLocalizationsOf(context).whatIsArDrive,
    );
  }
}

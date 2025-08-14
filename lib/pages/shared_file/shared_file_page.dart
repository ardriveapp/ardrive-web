import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/file_revision_base.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../components/details_panel.dart';
import '../drive_detail/components/drive_explorer_item_tile.dart';

/// [SharedFilePage] displays details of a shared file and controls for downloading and previewing it
/// from a parent [SharedFileCubit].
class SharedFilePage extends StatelessWidget {
  final _fileKeyController = TextEditingController();

  SharedFilePage({super.key}) {
    PlausibleEventTracker.trackPageview(page: PlausiblePageView.sharedFilePage);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: BlocConsumer<SharedFileCubit, SharedFileState>(
        buildWhen: (previous, current) {
          return current is! SharedFileKeyInvalid;
        },
        listener: (context, state) {
          if (state is SharedFileKeyInvalid) {
            showArDriveDialog(
              context,
              content: ArDriveStandardModal(
                title: appLocalizationsOf(context).error,
                description: appLocalizationsOf(context).invalidKeyFile,
              ),
            );
          }
        },
        builder: (context, state) {
          Widget activityPanel(SharedFileLoadSuccess state) {
            return DetailsPanel(
              item: DriveDataTableItemMapper.fromRevision(
                FileRevisionBase.fromFileRevision(state.fileRevisions.first),
                false,
              ),
              isSharePage: true,
              fileKey: state.fileKey,
              revisions: state.fileRevisions,
              licenseState: state.latestLicense,
              ownerAddress: state.ownerAddress,
              drivePrivacy: state.fileKey != null ? 'private' : 'public',
              canNavigateThroughImages: false,
            );
          }

          return ScreenTypeLayout.builder(
            desktop: (context) => Container(
              color:
                  ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (state is SharedFileLoadSuccess) ...{
                      Flexible(
                        flex: 1,
                        child: activityPanel(state),
                      )
                    } else ...{
                      _buildShareCard(context, state)
                    }
                  ],
                ),
              ),
            ),
            mobile: (context) => SizedBox(
              height: MediaQuery.of(context).size.height,
              child: state is SharedFileLoadSuccess
                  ? Row(children: [Expanded(child: activityPanel(state))])
                  : _buildShareCard(context, state),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShareCard(BuildContext context, SharedFileState state) {
    return ArDriveCard(
      backgroundColor:
          ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
      elevation: 2,
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 400,
              minWidth: kMediumDialogWidth,
              minHeight: 256,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ScreenTypeLayout.builder(
                  desktop: (context) => Row(
                    children: [
                      ArDriveImage(
                        image: AssetImage(
                          // TODO: replace with ArDriveTheme .isLight method
                          ArDriveTheme.of(context).themeData.name == 'light'
                              ? Resources.images.brand.blackLogo2
                              : Resources.images.brand.whiteLogo2,
                        ),
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                  mobile: (context) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ArDriveImage(
                        image: AssetImage(
                          // TODO: replace with ArDriveTheme .isLight method
                          ArDriveTheme.of(context).themeData.name == 'light'
                              ? Resources.images.brand.blackLogo2
                              : Resources.images.brand.whiteLogo2,
                        ),
                        height: 55,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                if (state is SharedFileIsPrivate) ...[
                  Text(appLocalizationsOf(context).sharedFileIsEncrypted),
                  const SizedBox(height: 16),
                  ArDriveTextField(
                    controller: _fileKeyController,
                    autofocus: true,
                    obscureText: true,
                    hintText: appLocalizationsOf(context).enterFileKey,
                    onFieldSubmitted: (_) => context
                        .read<SharedFileCubit>()
                        .submit(_fileKeyController.text),
                  ),
                  const SizedBox(height: 16),
                  ArDriveButton(
                    onPressed: () => context
                        .read<SharedFileCubit>()
                        .submit(_fileKeyController.text),
                    text: appLocalizationsOf(context).unlock,
                  ),
                ],
                if (state is SharedFileLoadInProgress)
                  const CircularProgressIndicator()
                else if (state is SharedFileLoadSuccess) ...{
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: DriveExplorerItemTileLeading(
                      item: DriveDataTableItemMapper.fromRevision(
                        FileRevisionBase.fromFileRevision(
                            state.fileRevisions.first),
                        false, // in this page we don't have the information about the current drive, so it's impossible to know if the file is from the user logged in
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
                    icon: ArDriveIcons.download(color: Colors.white),
                    onPressed: () {
                      final file = ARFSFactory().getARFSFileFromFileRevision(
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
                    appLocalizationsOf(context).specifiedFileDoesNotExist,
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

  Widget _buildReturnToAppLink(BuildContext context) {
    return ArDriveButton(
      style: ArDriveButtonStyle.tertiary,
      onPressed: () => openUrl(url: Resources.ardrivePublicSiteLink),
      text: appLocalizationsOf(context).whatIsArDrive,
    );
  }
}

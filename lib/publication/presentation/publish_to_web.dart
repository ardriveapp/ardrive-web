import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/drive_picker/drive_picker_cubit.dart';
import 'package:ardrive/components/drive_picker/drive_picker_dialog.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/presentation/publications_cubit.dart';
import 'package:ardrive/publication/presentation/publish/publish_dialog.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Whether "Publish to web" is offered for [drive] (docs/PUBLICATIONS.md,
/// "Entry points"): on the web, in the app rather than a publication, to the
/// owner of a public drive, where snapshots can be published at all.
bool offersPublishToWeb(BuildContext context, Drive? drive) =>
    drive != null &&
    kIsWeb &&
    !PublicationMode.isOn &&
    context.read<ConfigService>().config.enableDriveStatePublishing &&
    context.read<PublicationsCubit>().canPublish(drive);

/// Whether "Publish to web" is offered for a file: as for a drive, to the
/// file's owner in a public or a private drive, for a file whose data is
/// theirs (a pinned file's belongs to someone else).
bool offersPublishFileToWeb(
  BuildContext context,
  Drive? drive, {
  required String? pinnedDataOwnerAddress,
}) =>
    drive != null &&
    kIsWeb &&
    !PublicationMode.isOn &&
    pinnedDataOwnerAddress == null &&
    context.read<ConfigService>().config.enableDriveStatePublishing &&
    context.read<PublicationsCubit>().canPublishFile(drive);

/// What a drive's, a folder's or a file's publication is, as the cubit's
/// state holds it.
Publication? _publicationIn(
  PublicationsState state,
  String driveId, {
  String? folderId,
  String? fileId,
}) =>
    fileId != null
        ? state.filePageOf(driveId, fileId)
        : state.publicationOf(driveId, folderId);

/// "Published to web" once [folderId] (or the drive, when null) or [fileId]
/// is published, else "Publish to web".
String publishToWebLabel(
  BuildContext context,
  Drive drive,
  String? folderId, {
  String? fileId,
}) {
  final strings = appLocalizationsOf(context);
  return _publicationIn(context.read<PublicationsCubit>().state, drive.id,
              folderId: folderId, fileId: fileId) !=
          null
      ? strings.publishedToWeb
      : strings.publishToWeb;
}

/// The web page with an upward arrow that stands for publishing to the web.
ArDriveIcon publishToWebIcon({double? size, Color? color}) =>
    ArDriveIcons.publishToWeb(size: size ?? 24, color: color);

/// Opens publishing for [drive], for its folder [folderId] or for its file
/// [fileId].
Future<void> openPublishToWeb(
  BuildContext context, {
  required Drive drive,
  String? folderId,
  String? fileId,
}) async {
  if (fileId != null) {
    final file = await context
        .read<DriveDao>()
        .fileById(fileId: fileId)
        .getSingleOrNull();
    if (file == null || !context.mounted) return;
    return promptToPublish(context, drive: drive, file: file);
  }
  FolderEntry? folder;
  if (folderId != null && folderId != drive.rootFolderId) {
    folder = await context
        .read<DriveDao>()
        .folderById(folderId: folderId)
        .getSingleOrNull();
    if (folder == null || !context.mounted) return;
  }
  if (!context.mounted) return;
  await promptToPublish(context, drive: drive, folder: folder);
}

/// The drives Publish on the Web pages page offers: of the user's own
/// [drives], those not hidden that [canPublish] (public ones, where
/// publishing is on).
List<Drive> publishPickerDrives(
  List<Drive> drives, {
  required bool Function(Drive drive) canPublish,
}) =>
    [
      for (final drive in drives)
        if (!drive.isHidden && canPublish(drive)) drive,
    ];

/// Whether the publish picker lets [file] be chosen: not a pinned file,
/// whose data belongs to someone else.
bool publishPickerCanChooseFile(DrivePickerEntry file) => !file.isPinned;

/// Publish on the Web pages page: the drive picker, to choose a public
/// drive, folder or file, then the same publishing its menu opens. Opens on
/// the drive and folder last open, when that drive can be published.
///
/// Only public drives are offered, as a private drive's and folder's menus
/// offer no publishing. A private file's page is still published from its
/// own menu.
///
/// [canPublish] defaults to [offersPublishToWeb], which is only ever true on
/// the web; a test hands in its own.
Future<void> pickAndPublishToWeb(
  BuildContext context, {
  bool Function(Drive drive)? canPublish,
}) {
  final strings = appLocalizationsOf(context);
  final router = context.read<AppRouterDelegate>();
  final drivesState = context.read<DrivesCubit>().state;
  final syncCubit = context.read<SyncCubit>();
  final drives = drivesState is DrivesLoadSuccess
      ? publishPickerDrives(
          drivesState.userDrives,
          canPublish:
              canPublish ?? (drive) => offersPublishToWeb(context, drive),
        )
      : const <Drive>[];
  return showDrivePicker(
    context,
    title: strings.publishToWeb,
    purpose: DrivePickerPurpose.publish,
    drives: drives,
    driveId: router.driveId,
    folderId: router.driveFolderId,
    noDrivesMessage: strings.noPublicDrives,
    canChooseFile: publishPickerCanChooseFile,
    sync: (drive) => syncCubit.startSyncForDrive(driveId: drive.id),
    syncRefusal: () => syncCubit.lastSingleSyncRefusal,
    actionLabel: (state) => state.fileId != null
        ? strings.webPagesPublishFile
        : state.folder == null
            ? strings.webPagesPublish
            : state.atRoot
                ? strings.webPagesPublishDrive
                : strings.webPagesPublishFolder,
    onChoose: (choice) {
      if (!context.mounted) return;
      openPublishToWeb(
        context,
        drive: choice.drive,
        folderId: choice.folder.id,
        fileId: choice.fileId,
      );
    },
  );
}

/// A small web page mark beside a published drive or folder, "Published to web" on
/// hover. Nothing when it is not published.
class PublishedToWebMark extends StatelessWidget {
  const PublishedToWebMark({
    super.key,
    required this.driveId,
    this.folderId,
    this.size = 14,
    this.leadingGap = ArDriveSpacing.xs,
  });

  final String driveId;

  /// The space before the mark. Zero where it sits in a list of marks that
  /// spaces them already, as a drive row's name does: with its own gap on
  /// top it sat further out than the tag beside it.
  final double leadingGap;

  /// Null for the drive itself.
  final String? folderId;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (PublicationMode.isOn) return const SizedBox.shrink();
    // Rows are also built where nothing publishes (a widget on its own, in a
    // test); there is nothing to mark there.
    final PublicationsCubit cubit;
    try {
      cubit = context.read<PublicationsCubit>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    return BlocBuilder<PublicationsCubit, PublicationsState>(
      bloc: cubit,
      buildWhen: (a, b) =>
          (a.publicationOf(driveId, folderId) != null) !=
          (b.publicationOf(driveId, folderId) != null),
      builder: (context, state) {
        if (state.publicationOf(driveId, folderId) == null) {
          return const SizedBox.shrink();
        }
        final colors = ArDriveTheme.of(context).themeData.colorTokens;
        return Padding(
          padding: EdgeInsetsDirectional.only(start: leadingGap),
          child: ArDriveTooltip(
            message: appLocalizationsOf(context).publishedToWeb,
            child: publishToWebIcon(size: size, color: colors.iconMid),
          ),
        );
      },
    );
  }
}

/// The menu item, worded from what is published right now: a publish that
/// just finished turns it into "Published to web" without the menu being
/// rebuilt.
class PublishToWebMenuItem extends StatelessWidget {
  const PublishToWebMenuItem({
    super.key,
    required this.drive,
    this.folderId,
    this.fileId,
    required this.iconSize,
    this.height,
  });

  final Drive drive;

  /// Null for the drive itself.
  final String? folderId;

  /// Set for a file.
  final String? fileId;
  final double iconSize;
  final double? height;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PublicationsCubit, PublicationsState>(
        buildWhen: (a, b) =>
            (_publicationIn(a, drive.id, folderId: folderId, fileId: fileId) !=
                null) !=
            (_publicationIn(b, drive.id, folderId: folderId, fileId: fileId) !=
                null),
        builder: (context, _) => ArDriveDropdownItemTile(
          name: publishToWebLabel(context, drive, folderId, fileId: fileId),
          icon: publishToWebIcon(size: iconSize),
          height: height,
        ),
      );
}

/// A button in the publish dialogs: the dialogs' own secondary button, as
/// wide as its label needs.
Widget publishButton(
  BuildContext context,
  String text, {
  required VoidCallback onPressed,
  ButtonVariant variant = ButtonVariant.secondary,
}) =>
    ArDriveButtonNew(
      text: text,
      typography: ArDriveTypographyNew.of(context),
      variant: variant,
      maxWidth: ArDriveButtonNew.fittedWidth(context, text, minWidth: 96),
      onPressed: onPressed,
    );

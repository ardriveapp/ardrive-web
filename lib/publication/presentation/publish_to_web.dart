import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
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

/// "Published to web" once [folderId] (or the drive, when null) is
/// published, else "Publish to web".
String publishToWebLabel(BuildContext context, Drive drive, String? folderId) {
  final strings = appLocalizationsOf(context);
  return context
              .read<PublicationsCubit>()
              .state
              .publicationOf(drive.id, folderId) !=
          null
      ? strings.publishedToWeb
      : strings.publishToWeb;
}

/// The web page with an upward arrow that stands for publishing to the web.
ArDriveIcon publishToWebIcon({double? size, Color? color}) =>
    ArDriveIcons.publishToWeb(size: size ?? 24, color: color);

/// Opens publishing for [drive], or for its folder [folderId].
Future<void> openPublishToWeb(
  BuildContext context, {
  required Drive drive,
  String? folderId,
}) async {
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

/// A small web page mark beside a published drive or folder, "Published to web" on
/// hover. Nothing when it is not published.
class PublishedToWebMark extends StatelessWidget {
  const PublishedToWebMark({
    super.key,
    required this.driveId,
    this.folderId,
    this.size = 14,
  });

  final String driveId;

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
          padding: const EdgeInsetsDirectional.only(start: 6),
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
    required this.iconSize,
    this.height,
  });

  final Drive drive;

  /// Null for the drive itself.
  final String? folderId;
  final double iconSize;
  final double? height;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PublicationsCubit, PublicationsState>(
        buildWhen: (a, b) =>
            (a.publicationOf(drive.id, folderId) != null) !=
            (b.publicationOf(drive.id, folderId) != null),
        builder: (context, _) => ArDriveDropdownItemTile(
          name: publishToWebLabel(context, drive, folderId),
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

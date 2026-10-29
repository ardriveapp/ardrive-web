import 'package:ardrive/publication/domain/file_page.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/presentation/publish/publish_dialog.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A published drive or folder (docs/PUBLICATIONS.md, "Management"): its
/// link, when it was published, Update, and earlier versions.
Future<void> showPublishedView(
  BuildContext context, {
  required Drive drive,
  FolderEntry? folder,
  FileEntry? file,
  required Publication publication,
}) =>
    showArDriveDialog(
      context,
      content: PublishedView(
        drive: drive,
        folder: folder,
        file: file,
        publication: publication,
        // From the caller's context: the view's own is gone once it closes.
        onUpdate: () {
          // The menu or row this opened from can be rebuilt away while the
          // view is open.
          if (!context.mounted) return;
          showPublishDialog(
            context,
            drive: drive,
            folder: folder,
            file: file,
            previous: publication,
          );
        },
      ),
    );

class PublishedView extends StatefulWidget {
  const PublishedView({
    super.key,
    required this.drive,
    required this.folder,
    this.file,
    required this.publication,
    required this.onUpdate,
  });

  final Drive drive;
  final FolderEntry? folder;

  /// The file a file page shows.
  final FileEntry? file;
  final Publication publication;

  /// Opens the publish dialog as an update, on the look: one way in, where
  /// Next keeps the look and anything changed is changed first.
  final VoidCallback onUpdate;

  @override
  State<PublishedView> createState() => _PublishedViewState();
}

class _PublishedViewState extends State<PublishedView> {
  late final Future<PublishedContent?> _content = context
      .read<PublicationRepository>()
      .readContent(widget.publication.latest.txId)
      .then<PublishedContent?>((c) => c)
      .catchError((_) => null);
  bool _showEarlier = false;

  /// A private file page's links carry the file's key, for the owner.
  String? _fileKey;

  /// A file page made from an earlier version of its file.
  bool _outOfDate = false;

  /// Whether a private file page's key has been looked for: its link is not
  /// shown, or copied, without it.
  bool _keyChecked = false;

  bool get _isPrivateFile => widget.file != null && widget.drive.isPrivate;

  @override
  void initState() {
    super.initState();
    final file = widget.file;
    if (file == null) return;
    _checkFile(file);
  }

  Future<void> _checkFile(FileEntry file) async {
    final driveDao = context.read<DriveDao>();
    final profile = context.read<ProfileCubit>().state;
    final key = _isPrivateFile
        ? await fileKeyForLink(driveDao, profile,
            driveId: file.driveId, fileId: file.id)
        : null;
    // Out of date by the share page's own rule: the metadata it was made
    // from is not the file's latest.
    final revision = await driveDao
        .latestFileRevisionByFileId(driveId: file.driveId, fileId: file.id)
        .getSingleOrNull();
    final published = (await _content)?.config.file;
    if (!mounted) return;
    setState(() {
      _fileKey = key;
      _keyChecked = true;
      _outOfDate = revision != null &&
          published != null &&
          published.metadataTxId != revision.metadataTxId;
    });
  }

  String _link(String txId) => withFileKey(
      '${context.read<ConfigService>().config.publicationGatewayUrl}/$txId/',
      _fileKey);

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final latest = widget.publication.latest;
    final earlier = widget.publication.earlier;

    void update() {
      Navigator.of(context).pop();
      widget.onUpdate();
    }

    return ArDriveStandardModalNew(
      title: strings.publishedToWeb,
      width: 520,
      scrollableContent: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<PublishedContent?>(
            future: _content,
            builder: (context, snapshot) {
              final config = snapshot.data?.config;
              final date =
                  formatDate(config?.publishedAt ?? latest.publishedAt);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config?.title ??
                        widget.file?.name ??
                        widget.folder?.name ??
                        widget.drive.name,
                    style: typography.heading5(fontWeight: ArFontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    config?.fileCount != null
                        ? strings.publishedOnWithFiles(date, config!.fileCount!)
                        : strings.publishedOn(date),
                    style: typography.paragraphNormal(color: colors.textMid),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_outOfDate) ...[
            Text(strings.publishFileOutOfDate,
                style: typography.paragraphNormal(color: colors.textHigh)),
            const SizedBox(height: 12),
          ],
          if (_isPrivateFile && !_keyChecked)
            const SizedBox(
              height: 48,
              child: Center(child: ArDriveSpinner()),
            )
          else
            PublishedLink(
              link: _link(latest.txId),
              isSecret: _fileKey != null,
              note: [
                if (_fileKey != null) strings.publishFileKeyInLink,
                strings.publishUpdateNote,
              ].join(' '),
            ),
          if (earlier.isNotEmpty) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _showEarlier = !_showEarlier),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '${strings.publishEarlierVersions} (${earlier.length})',
                      style: typography.paragraphNormal(
                          color: colors.textHigh,
                          fontWeight: ArFontWeight.semiBold),
                    ),
                    const SizedBox(width: 4),
                    (_showEarlier
                            ? ArDriveIcons.chevronUp
                            : ArDriveIcons.chevronDown)(
                        size: 16, color: colors.iconMid),
                  ],
                ),
              ),
            ),
            if (_showEarlier)
              for (final version in earlier)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings
                              .publishedOn(formatDateTime(version.publishedAt)),
                          style:
                              typography.paragraphNormal(color: colors.textMid),
                        ),
                      ),
                      ArDriveClickArea(
                        child: GestureDetector(
                          onTap: () => openUrl(url: _link(version.txId)),
                          child: Text(
                            strings.publishOpen,
                            style: typography
                                .paragraphNormal(
                                  fontWeight: ArFontWeight.semiBold,
                                  color: colors.textMid,
                                )
                                .copyWith(decoration: TextDecoration.underline),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
      actions: [
        ModalAction(title: strings.publishUpdate, action: update),
        ModalAction(
          title: strings.publishOpenPage,
          action: () => openUrl(url: _link(latest.txId)),
        ),
        ModalAction(
          title: strings.doneEmphasized,
          action: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

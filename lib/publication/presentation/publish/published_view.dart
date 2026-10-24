import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/presentation/publish/publish_dialog.dart';
import 'package:ardrive/publication/presentation/publish_to_web.dart'
    show publishButton;
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A published drive or folder (docs/PUBLICATIONS.md, "Management"): its
/// link, when it was published, Update and Edit look, and earlier versions.
Future<void> showPublishedView(
  BuildContext context, {
  required Drive drive,
  FolderEntry? folder,
  required Publication publication,
}) =>
    showArDriveDialog(
      context,
      content: PublishedView(
        drive: drive,
        folder: folder,
        publication: publication,
        // From the caller's context: the view's own is gone once it closes.
        onUpdate: (look) => showPublishDialog(
          context,
          drive: drive,
          folder: folder,
          previous: publication,
          startAtLook: look,
        ),
      ),
    );

class PublishedView extends StatefulWidget {
  const PublishedView({
    super.key,
    required this.drive,
    required this.folder,
    required this.publication,
    required this.onUpdate,
  });

  final Drive drive;
  final FolderEntry? folder;
  final Publication publication;

  /// Opens the publish dialog as an update, on the look when true.
  final void Function(bool look) onUpdate;

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

  String _link(String txId) =>
      '${context.read<ConfigService>().config.arweaveGatewayForDataRequest.url}/$txId/';

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final latest = widget.publication.latest;
    final earlier = widget.publication.earlier;

    void reopen({required bool look}) {
      Navigator.of(context).pop();
      widget.onUpdate(look);
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
                    config?.title ?? widget.folder?.name ?? widget.drive.name,
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
          PublishedLink(link: _link(latest.txId)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              publishButton(
                context,
                strings.publishUpdate,
                onPressed: () => reopen(look: false),
              ),
              publishButton(
                context,
                strings.publishEditLook,
                onPressed: () => reopen(look: true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(strings.publishUpdateNote,
              style: typography.paragraphSmall(color: colors.textLow)),
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
                      publishButton(
                        context,
                        strings.publishOpen,
                        onPressed: () => openUrl(url: _link(version.txId)),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
      actions: [
        ModalAction(
          title: strings.close,
          action: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

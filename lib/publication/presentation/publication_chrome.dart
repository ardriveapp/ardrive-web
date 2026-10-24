import 'package:ardrive/components/icon_theme_switcher.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_stats.dart';
import 'package:ardrive/publication/presentation/publication_loader/publication_loader_cubit.dart';
import 'package:ardrive/publication/presentation/publication_loader_page.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The open publication's settings, or null before it is open and on every page
/// that is not a publication.
PublicationConfig? publicationConfigOf(BuildContext context) {
  final PublicationLoaderCubit cubit;
  try {
    cubit = context.read<PublicationLoaderCubit>();
  } on ProviderNotFoundException {
    return null;
  }
  final state = cubit.state;
  return state is PublicationReady ? state.config : null;
}

/// The publication's own link to a folder in it, and to a file in that folder:
/// `<page link>#/folders/<id>?file=<id>`, or `<page link>#/` for its root.
/// What "Copy link" copies on a publication, in place of Share.
String publicationLink({
  required Uri page,
  String? folderId,
  String? fileId,
}) {
  final route = folderId == null
      ? '/'
      : '/folders/$folderId${fileId == null ? '' : '?file=$fileId'}';
  return page.removeFragment().replace(fragment: route).toString();
}

/// "Copy link" on a publication: copies [publicationLink] for a folder, or for
/// a file in its folder, and says so.
Future<void> copyPublicationLink(
  BuildContext context, {
  required String folderId,
  String? fileId,
}) async {
  final config = publicationConfigOf(context);
  // The scope's root is the publication's own link, not a folder in it. So is
  // the drive's root, which drive-level menus name: in a folder publication it
  // is outside the publication, and its id is not the publication's to hand out.
  final atRoot = fileId == null &&
      (folderId == config?.scopeRootFolderId ||
          folderId == config?.rootFolderId);
  await Clipboard.setData(ClipboardData(
    text: publicationLink(
      page: Uri.base,
      folderId: atRoot ? null : folderId,
      fileId: fileId,
    ),
  ));
  if (context.mounted) _sayCopied(context);
}

/// The app's own "Copied!" snackbar, as a failed sync shows its message.
void _sayCopied(BuildContext context) {
  final typography = ArDriveTypographyNew.of(context);
  final colors = ArDriveTheme.of(context).themeData.colorTokens;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        appLocalizationsOf(context).copied,
        style: typography.paragraphNormal(color: colors.textHigh),
      ),
      backgroundColor: colors.containerL3,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// The publication's top bar controls, in place of the hide toggle, the sync
/// indicator and the account (docs/PUBLICATIONS.md, "The publication frame"):
/// the theme toggle and "Made with ArDrive". Search is the top bar's own.
class PublicationTopBarActions extends StatelessWidget {
  const PublicationTopBarActions({super.key, this.compact = false});

  /// On a phone "Made with ArDrive" is ArDrive's mark alone.
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IconThemeSwitcher(),
          SizedBox(width: compact ? 4 : 12),
          MadeWithArDrive(compact: compact),
        ],
      );
}

/// The one place a publication names ArDrive: a quiet button in the top
/// bar's corner, as shared-link pages put their maker's, opening ardrive.io.
class MadeWithArDrive extends StatelessWidget {
  const MadeWithArDrive({super.key, this.compact = false});

  final bool compact;

  static const url = 'https://ardrive.io';

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final mark = Image.asset(
      Resources.images.brand.logo1,
      width: compact ? 24 : 18,
      height: compact ? 24 : 18,
    );
    if (compact) {
      return Semantics(
        container: true,
        link: true,
        label: strings.publicationMadeWithArDrive,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => openUrl(url: url),
          child: HoverWidget(
            tooltip: strings.publicationMadeWithArDrive,
            child: mark,
          ),
        ),
      );
    }
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveButtonNew(
      text: strings.publicationMadeWithArDrive,
      typography: typography,
      variant: ButtonVariant.outline,
      maxHeight: 36,
      onPressed: () => openUrl(url: url),
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            mark,
            const SizedBox(width: 8),
            Text(
              strings.publicationMadeWithArDrive,
              style: typography.paragraphSmall(
                color: colors.textMid,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The head of a publication's root (docs/PUBLICATIONS.md, "The publication
/// frame"), in place of the breadcrumb row there: the cover as a banner, then
/// the title, who it is by, what is in it and its description, with the
/// root's actions beside the title. Text never sits on the cover, which may
/// be any picture.
///
/// [collapsed] once the list beneath has scrolled: the cover and the lines
/// under the title fold away and the title and actions stay, so the list
/// has the window.
class PublicationHeader extends StatelessWidget {
  const PublicationHeader({
    super.key,
    required this.coverHeight,
    required this.collapsed,
    required this.compact,
    required this.onDownload,
    required this.downloadsSelection,
    required this.onCopyLink,
  });

  final double coverHeight;
  final bool collapsed;

  /// A phone's: the actions are icons.
  final bool compact;
  final VoidCallback onDownload;

  /// Whether [onDownload] takes the rows selected in the list rather than the
  /// whole publication, which its label then says.
  final bool downloadsSelection;
  final VoidCallback onCopyLink;

  static const _fold = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final config = publicationConfigOf(context);
    if (config == null) return const SizedBox.shrink();
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cover = config.images.cover;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _Byline(config: config, stats: _statsOf(context)),
        if (config.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            config.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: typography.paragraphNormal(color: colors.textMid),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: _fold,
          alignment: Alignment.topCenter,
          child: cover == null || collapsed
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: coverHeight,
                      width: double.infinity,
                      child: Image.network(
                        Uri.base.resolve(cover).toString(),
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        frameBuilder: (context, image, frame, sync) =>
                            frame != null || sync
                                ? image
                                : const PublicationImagePlaceholder(),
                        errorBuilder: (_, __, ___) =>
                            const PublicationImagePlaceholder(),
                      ),
                    ),
                  ),
                ),
        ),
        // The actions beside the title only, so the lines under it have the
        // width.
        Row(
          children: [
            Expanded(
              child: Text(
                config.title,
                maxLines: collapsed ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: (collapsed ? typography.heading5 : typography.heading4)(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            _Actions(
              compact: compact,
              onDownload: onDownload,
              downloadsSelection: downloadsSelection,
              onCopyLink: onCopyLink,
            ),
          ],
        ),
        AnimatedSize(
          duration: _fold,
          alignment: Alignment.topCenter,
          child: collapsed ? const SizedBox(width: double.infinity) : details,
        ),
      ],
    );
  }

  static PublicationStats? _statsOf(BuildContext context) {
    try {
      final state = context.read<PublicationLoaderCubit>().state;
      return state is PublicationReady ? state.stats : null;
    } on ProviderNotFoundException {
      return null;
    }
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.compact,
    required this.onDownload,
    required this.downloadsSelection,
    required this.onCopyLink,
  });

  final bool compact;
  final VoidCallback onDownload;
  final bool downloadsSelection;
  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final download = downloadsSelection
        ? strings.publicationDownloadSelected
        : strings.download;
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArDriveIconButton(
            tooltip: download,
            icon: ArDriveIcons.download(),
            onPressed: onDownload,
          ),
          const SizedBox(width: 4),
          ArDriveIconButton(
            tooltip: strings.copyLink,
            icon: ArDriveIcons.copy(),
            onPressed: onCopyLink,
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LabelledButton(
          icon: ArDriveIcons.download(size: 20),
          label: download,
          onPressed: onDownload,
        ),
        const SizedBox(width: 8),
        _LabelledButton(
          icon: ArDriveIcons.copy(size: 20),
          label: strings.copyLink,
          onPressed: onCopyLink,
        ),
      ],
    );
  }
}

class _LabelledButton extends StatelessWidget {
  const _LabelledButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveButtonNew(
      text: label,
      typography: typography,
      variant: ButtonVariant.outline,
      maxHeight: 40,
      onPressed: onPressed,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 8),
            Text(
              label,
              style: typography.paragraphNormal(
                color: colors.textHigh,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "By <owner> • N files • size • published <date>". The owner is the name
/// they chose, or their address shortened; either way the whole address is
/// a hover away and a click copies it, since a typed name proves nothing.
class _Byline extends StatelessWidget {
  const _Byline({required this.config, required this.stats});

  final PublicationConfig config;
  final PublicationStats? stats;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final style = typography.paragraphNormal(color: colors.textMid);
    final owner = config.ownerName ??
        truncateString(config.owner, offsetStart: 6, offsetEnd: 4);
    final publishedAt = config.publishedAt;
    final stats = this.stats;

    // One line that wraps between words. Each bullet is held to the word
    // before it by a no-break space, so a wrapped line never starts with one.
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Tooltip(
              message: config.owner,
              // A screen reader reads the name; the whole address first was
              // 43 characters of noise.
              excludeFromSemantics: true,
              child: ArDriveClickArea(
                child: GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: config.owner));
                    if (context.mounted) _sayCopied(context);
                  },
                  child: Text(strings.publicationBy(owner), style: style),
                ),
              ),
            ),
          ),
          if (stats != null)
            TextSpan(
              text:
                  '\u00a0• ${(publishedAt == null ? strings.publicationCountSummary(
                      stats.fileCount,
                      filesize(stats.totalSize),
                    ) : strings.publicationCoverSummary(
                      stats.fileCount,
                      filesize(stats.totalSize),
                      formatDate(publishedAt),
                    )).replaceAll(' • ', '\u00a0• ')}',
            ),
        ],
      ),
    );
  }
}

import 'package:ardrive/components/icon_theme_switcher.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_stats.dart';
import 'package:ardrive/publication/presentation/publication_loader/publication_loader_cubit.dart';
import 'package:ardrive/publication/presentation/publication_loader_page.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/config/config_service.dart';
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
  showArDriveToast(
    ScaffoldMessenger.of(context),
    text: appLocalizationsOf(context).copied,
    type: ArDriveStatusType.success,
    duration: const Duration(seconds: 2),
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
      size: ArDriveButtonSize.compact,
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
              style: typography.paragraphNormal(
                color: colors.textMid,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
            // It leaves the publication for ardrive.io, in a new window.
            const SizedBox(width: ArDriveSpacing.xxs),
            ExcludeSemantics(
              child: ArDriveIcons.newWindow(size: 16, color: colors.textMid),
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
    final cover = collapsed ? null : config.images.cover;
    final icon = collapsed ? null : config.images.icon;

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

    // The actions beside the title only, so the lines under it have the
    // width.
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (!collapsed) details,
      ],
    );

    final Widget head;
    if (cover != null && icon != null) {
      head = PublicationCoverLayout(
        cover: _CoverImage(path: cover, height: coverHeight),
        icon: _HeaderIcon(path: icon, size: compact ? 64 : 88),
        iconSize: compact ? 64 : 88,
        ringWidth: 4,
        ringColor: colors.containerL0,
        inset: compact ? 12 : 16,
        // A phone's title block gets the full width, below the icon.
        beside: !compact,
        body: titleBlock,
      );
    } else if (cover != null) {
      head = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverImage(path: cover, height: coverHeight),
          const SizedBox(height: 16),
          titleBlock,
        ],
      );
    } else if (icon != null) {
      final size = compact ? 48.0 : 56.0;
      head = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderIcon(path: icon, size: size),
          SizedBox(width: compact ? ArDriveSpacing.sm : ArDriveSpacing.md),
          Expanded(child: titleBlock),
        ],
      );
    } else {
      head = titleBlock;
    }

    return AnimatedSize(
      duration: _fold,
      alignment: Alignment.topCenter,
      child: head,
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

/// The head of a file page (docs/PUBLICATIONS.md, "File pages"), above its
/// file, in place of the share page's wordmark: the cover, the title, who it
/// is by and its description. The file's own card says what the file is.
class PublicationFileHead extends StatelessWidget {
  const PublicationFileHead({super.key, required this.config});

  final PublicationConfig config;

  /// Below this width the head is a phone's: a smaller icon, with the title
  /// below it rather than beside it.
  static const _compactBelow = 560.0;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final cover = config.images.cover;
    final icon = config.images.icon;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          config.title,
          style: typography.heading4(
              color: colors.textHigh, fontWeight: ArFontWeight.bold),
        ),
        const SizedBox(height: 4),
        _Byline(config: config, stats: null),
        if (config.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(config.description,
              style: typography.paragraphNormal(color: colors.textMid)),
        ],
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < _compactBelow;
      if (cover != null && icon != null) {
        final size = compact ? 64.0 : 88.0;
        return PublicationCoverLayout(
          cover: _CoverImage(path: cover, aspectRatio: 4),
          icon: _HeaderIcon(path: icon, size: size),
          iconSize: size,
          ringWidth: 4,
          // The share page's own surface, behind the head.
          ringColor:
              ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
          inset: compact ? 12 : 16,
          beside: !compact,
          body: text,
        );
      }
      if (cover != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CoverImage(path: cover, aspectRatio: 4),
            const SizedBox(height: 16),
            text,
          ],
        );
      }
      if (icon != null) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderIcon(path: icon, size: compact ? 48 : 56),
            SizedBox(width: compact ? ArDriveSpacing.sm : ArDriveSpacing.md),
            Expanded(child: text),
          ],
        );
      }
      return text;
    });
  }
}

/// A publication's cover as a banner, with its rounded corners: [height] tall,
/// or [aspectRatio] wide to high. A square holds its place while it loads.
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.path, this.height, this.aspectRatio});

  final String path;
  final double? height;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      Uri.base.resolve(path).toString(),
      fit: BoxFit.cover,
      alignment: Alignment.center,
      frameBuilder: (context, image, frame, sync) =>
          frame != null || sync ? image : const PublicationImagePlaceholder(),
      errorBuilder: (_, __, ___) => const PublicationImagePlaceholder(),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: aspectRatio != null
          ? AspectRatio(aspectRatio: aspectRatio!, child: image)
          : SizedBox(height: height, width: double.infinity, child: image),
    );
  }
}

/// A publication's icon in the head: a rounded square. Unlike
/// [PublicationIcon] it never falls back to ArDrive's mark, which would read
/// as the page's maker; a square holds its place instead.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.path, required this.size});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = PublicationImagePlaceholder(width: size, height: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ArDriveRadius.md),
      child: Image.network(
        Uri.base.resolve(path).toString(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        frameBuilder: (context, image, frame, sync) =>
            frame != null || sync ? image : placeholder,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

/// A cover with the publication's icon cut into its bottom-left edge, half on
/// the cover and half below it, as on a profile page. [ringColor] is the
/// surface behind the head, drawn round the icon so it reads as cut out. The
/// [body] (title and the lines under it) sits beside the lower half of the
/// icon when [beside], else below it, so nothing collides with the overlap.
class PublicationCoverLayout extends StatelessWidget {
  const PublicationCoverLayout({
    super.key,
    required this.cover,
    required this.icon,
    required this.iconSize,
    required this.ringWidth,
    required this.ringColor,
    required this.inset,
    required this.beside,
    required this.body,
    this.iconRadius = ArDriveRadius.md,
    this.gap = ArDriveSpacing.md,
    this.bodyTop = ArDriveSpacing.sm,
  });

  /// The cover, sized by its own constraints.
  final Widget cover;

  /// The icon, [iconSize] square, without its ring.
  final Widget icon;
  final double iconSize;
  final double ringWidth;
  final Color ringColor;

  /// From the cover's left edge to the icon's ring.
  final double inset;
  final bool beside;
  final Widget body;

  /// The icon's own corner radius; the ring is concentric with it.
  final double iconRadius;

  /// From the icon's right edge to the [body] when [beside].
  final double gap;

  /// From the cover's bottom edge to the [body] when [beside].
  final double bodyTop;

  @override
  Widget build(BuildContext context) {
    final outer = iconSize + ringWidth * 2;
    final overlap = outer / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            cover,
            Positioned(
              left: inset,
              bottom: -overlap,
              child: Container(
                padding: EdgeInsets.all(ringWidth),
                decoration: BoxDecoration(
                  color: ringColor,
                  borderRadius: BorderRadius.circular(iconRadius + ringWidth),
                ),
                child: icon,
              ),
            ),
          ],
        ),
        if (beside)
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: overlap + ArDriveSpacing.xs),
            child: Padding(
              padding: EdgeInsets.only(left: inset + outer + gap, top: bodyTop),
              child: body,
            ),
          )
        else ...[
          SizedBox(height: overlap + ArDriveSpacing.xs),
          body,
        ],
      ],
    );
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

/// "By <owner> · N files · size · published <date>". The owner is the name
/// they chose when there is one, then their address shortened, since a typed
/// name proves nothing; the whole address is a hover away and a click
/// copies it. The address is the identity: a page whose snapshot someone
/// else signed is refused before it gets here.
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
    final address = shortenId(config.owner);
    final publishedAt = config.publishedAt;
    final stats = this.stats;

    // One line that wraps between words. Each middle dot is held to the word
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
                  child: PublicationOwnerLabel(
                    name: config.ownerName,
                    address: address,
                    style: style,
                    idStyle: typography.code(color: colors.textLow),
                  ),
                ),
              ),
            ),
          ),
          // A file page has no counts, only its date.
          if (stats == null && publishedAt != null)
            TextSpan(
                text:
                    '\u00a0· ${strings.publishedOn(formatDate(publishedAt))}'),
          if (stats != null)
            TextSpan(
              text:
                  '\u00a0· ${(publishedAt == null ? strings.publicationCountSummary(
                      stats.fileCount,
                      filesize(stats.totalSize),
                    ) : strings.publicationCoverSummary(
                      stats.fileCount,
                      filesize(stats.totalSize),
                      formatDate(publishedAt),
                    )).replaceAll(' · ', '\u00a0· ')}',
            ),
          // The licence its owner set for everything in it, named and linked
          // to the transaction that defines it.
          if (config.license case final license?) ...[
            const TextSpan(text: '\u00a0· '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Tooltip(
                message: license.name,
                child: ArDriveClickArea(
                  child: GestureDetector(
                    onTap: () => openUrl(
                      url:
                          '${context.read<ConfigService>().config.arweaveGatewayForDataRequest.url}'
                          '/${license.definitionTxId}',
                    ),
                    child: Text(
                      license.shortName,
                      style: style.copyWith(
                        decoration: TextDecoration.underline,
                        decorationColor: colors.textMid,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "By <name>", then a wallet icon and the shortened [address] in monospace,
/// lighter than the name: the address is the identity, so it is always there,
/// and a typed name never runs into it. Without a [name] it is "By", the icon
/// and the address.
class PublicationOwnerLabel extends StatelessWidget {
  const PublicationOwnerLabel({
    super.key,
    required this.name,
    required this.address,
    required this.style,
    required this.idStyle,
  });

  final String? name;
  final String address;

  /// The body face of "By <name>".
  final TextStyle style;

  /// The monospace face of the address, in the colour of the wallet icon.
  final TextStyle idStyle;

  @override
  Widget build(BuildContext context) {
    final by = appLocalizationsOf(context).publicationBy(name ?? '').trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(by, style: style)),
        const SizedBox(width: ArDriveSpacing.xs),
        // A screen reader reads the name and the address, not the icon.
        ExcludeSemantics(
          child: Icon(
            Icons.account_balance_wallet_outlined,
            size: (style.fontSize ?? 14) * 1.15,
            color: idStyle.color,
          ),
        ),
        const SizedBox(width: ArDriveSpacing.xxs),
        ArDriveIdText(address, style: idStyle),
      ],
    );
  }
}

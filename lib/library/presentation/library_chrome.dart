import 'package:ardrive/components/icon_theme_switcher.dart';
import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/presentation/library_loader/library_loader_cubit.dart';
import 'package:ardrive/library/presentation/library_loader_page.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// The open library's settings, or null before it is open and on every page
/// that is not a library page.
LibraryConfig? libraryConfigOf(BuildContext context) {
  final LibraryLoaderCubit cubit;
  try {
    cubit = context.read<LibraryLoaderCubit>();
  } on ProviderNotFoundException {
    return null;
  }
  final state = cubit.state;
  return state is LibraryReady ? state.config : null;
}

/// The library's own link to a folder in it, and to a file in that folder:
/// `<page link>#/folders/<id>?file=<id>`, or `<page link>#/` for its root.
/// What "Copy link" copies on a library page, in place of Share.
String libraryLink({
  required Uri page,
  String? folderId,
  String? fileId,
}) {
  final route = folderId == null
      ? '/'
      : '/folders/$folderId${fileId == null ? '' : '?file=$fileId'}';
  return page.removeFragment().replace(fragment: route).toString();
}

/// "Copy link" on a library page: copies [libraryLink] for a folder, or for
/// a file in its folder, and says so.
Future<void> copyLibraryLink(
  BuildContext context, {
  required String folderId,
  String? fileId,
}) async {
  final config = libraryConfigOf(context);
  // The scope's root is the library's own link, not a folder in it.
  final atRoot = fileId == null && folderId == config?.scopeRootFolderId;
  await Clipboard.setData(ClipboardData(
    text: libraryLink(
      page: Uri.base,
      folderId: atRoot ? null : folderId,
      fileId: fileId,
    ),
  ));
  if (!context.mounted) return;
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

/// "Open in ArDrive": the library's drive in the app, which a visitor opens
/// without signing in.
String openInArDriveUrl(String driveId) =>
    '${LibraryLoaderPage.ardriveUrl}/#/drives/$driveId';

/// The library's sidebar, in place of the drives list, the New button and the
/// account (docs/LIBRARY_PAGES.md, "The library frame"): the icon, the title,
/// the description and when it was published, then "Open in ArDrive" and
/// "Made with ArDrive", and the collapse control. A drawer on a phone.
class LibrarySideBar extends StatefulWidget {
  const LibrarySideBar({super.key});

  @override
  State<LibrarySideBar> createState() => _LibrarySideBarState();
}

class _LibrarySideBarState extends State<LibrarySideBar> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    final config = libraryConfigOf(context);
    return Material(
      color: theme.backgroundColor,
      child: ScreenTypeLayout.builder(
        mobile: (context) => Drawer(
          backgroundColor: theme.backgroundColor,
          elevation: 3,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _content(context, config, expanded: true),
            ),
          ),
        ),
        desktop: (context) => Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: theme.colors.shadow, width: 1),
            ),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: SizedBox(
              width: _isExpanded ? 240 : 64,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _isExpanded ? 24 : 8,
                  vertical: 24,
                ),
                child: _content(context, config, expanded: _isExpanded),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    LibraryConfig? config, {
    required bool expanded,
  }) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);
    final isDesktop =
        getDeviceType(MediaQuery.of(context).size) != DeviceScreenType.mobile;

    final collapse = isDesktop
        ? ArDriveIconButton(
            tooltip: expanded ? strings.collapseSideBar : strings.expandSideBar,
            icon: expanded
                ? ArDriveIcons.arrowLeftFilled()
                : ArDriveIcons.arrowRightFilled(),
            onPressed: () => setState(() => _isExpanded = !_isExpanded),
          )
        : null;

    if (!expanded) {
      return Column(
        children: [
          LibraryIcon(config: config, size: 40),
          const Spacer(),
          if (collapse != null) collapse,
        ],
      );
    }

    final publishedAt = config?.publishedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibraryIcon(config: config, size: 48),
        const SizedBox(height: 16),
        if (config != null) ...[
          Text(
            config.title,
            style: typography.heading5(
              color: colors.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
          if (config.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              config.description,
              style: typography.paragraphNormal(color: colors.textMid),
            ),
          ],
          if (publishedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              strings.libraryPublished(formatDate(publishedAt)),
              style: typography.paragraphSmall(color: colors.textLow),
            ),
          ],
        ],
        const Spacer(),
        if (config != null)
          ArDriveClickArea(
            child: GestureDetector(
              onTap: () => openUrl(url: openInArDriveUrl(config.driveId)),
              child: Text(
                strings.libraryOpenInArDrive,
                style: typography
                    .paragraphNormal(
                      color: colors.textHigh,
                      fontWeight: ArFontWeight.semiBold,
                    )
                    .copyWith(decoration: TextDecoration.underline),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ArDriveClickArea(
                child: GestureDetector(
                  onTap: () => openUrl(url: LibraryLoaderPage.ardriveUrl),
                  child: Text(
                    strings.libraryMadeWithArDrive,
                    style: typography.paragraphSmall(color: colors.textLow),
                  ),
                ),
              ),
            ),
            if (collapse != null) collapse,
          ],
        ),
      ],
    );
  }
}

/// The library's top bar controls, in place of the hide toggle, the sync
/// indicator and the account: the theme toggle. Search is the top bar's own.
class LibraryTopBarActions extends StatelessWidget {
  const LibraryTopBarActions({super.key});

  @override
  Widget build(BuildContext context) => const IconThemeSwitcher();
}

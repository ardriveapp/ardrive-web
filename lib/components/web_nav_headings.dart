import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/names_page/names_page.dart';
import 'package:ardrive/components/nav_sections.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_rail.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/web_pages/presentation/web_pages_cubit.dart';
import 'package:ardrive/web_pages/presentation/web_pages_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// How many items a heading lists before "Show all N": the nav is for
/// getting somewhere, and the page lists the rest.
const webNavItemLimit = 8;

/// Below the drives: what the reader has put on the web. Two headings of
/// their own, Web pages and Names, each opening its page from its words
/// and listing its first few items under the chevron (docs/NAMES.md,
/// "Where it lives").
class WebNavHeadings extends StatelessWidget {
  const WebNavHeadings({super.key, required this.showLabel});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final webPages = AppRouterDelegate.webPagesAreOn(context);
    final names = AppRouterDelegate.namesPageIsOn(context);
    if (!webPages && !names) return const SizedBox.shrink();
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Divider(height: 1, color: colorTokens.strokeLow),
        const SizedBox(height: 6),
        if (webPages) WebPagesNavHeading(showLabel: showLabel),
        if (names) NamesNavHeading(showLabel: showLabel),
      ],
    );
  }
}

/// One heading and the items under it, the way a drive sits under Public.
class _WebNavSection extends StatefulWidget {
  const _WebNavSection({
    required this.section,
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.isCurrent,
    required this.onOpen,
    required this.items,
  });

  /// Which heading this is, for remembering whether it is folded.
  final NavSection section;
  final IconData icon;
  final String label;
  final bool showLabel;
  final bool isCurrent;
  final VoidCallback onOpen;

  /// Every item; the first [webNavItemLimit] are listed.
  final List<Widget> items;

  @override
  State<_WebNavSection> createState() => _WebNavSectionState();
}

class _WebNavSectionState extends State<_WebNavSection> with FoldsNavSections {
  @override
  Widget build(BuildContext context) {
    // The collapsed rail has no room for the items: the icon opens the page.
    if (!widget.showLabel) {
      return DriveNavRow(
        icon: widget.icon,
        label: widget.label,
        showLabel: false,
        isCurrent: widget.isCurrent,
        onTap: widget.onOpen,
      );
    }
    final items = widget.items;
    // No chevron with nothing under it: it would fold away nothing.
    final hasItems = items.isNotEmpty;
    final isExpanded = !isFolded(widget.section);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DriveNavRow(
          icon: widget.icon,
          label: widget.label,
          isCurrent: widget.isCurrent,
          onTap: widget.onOpen,
          isExpanded: hasItems ? isExpanded : null,
          onToggle: hasItems ? () => toggleFolded(widget.section) : null,
        ),
        if (hasItems && isExpanded) ...[
          ...items.take(webNavItemLimit),
          if (items.length > webNavItemLimit)
            DriveNavRow(
              icon: null,
              dense: true,
              isMuted: true,
              label: appLocalizationsOf(context).webPagesShowAll(items.length),
              onTap: widget.onOpen,
            ),
        ],
      ],
    );
  }
}

void _closeDrawer(BuildContext context) {
  if (Scaffold.maybeOf(context) != null) {
    Scaffold.of(context).closeDrawer();
  }
}

/// Web pages: publications and deployments, most recently updated first.
class WebPagesNavHeading extends StatelessWidget {
  const WebPagesNavHeading({super.key, required this.showLabel});

  final bool showLabel;

  static const icon = ArDriveIconsData.publish_to_web;

  @override
  Widget build(BuildContext context) {
    final router = context.watch<AppRouterDelegate>();
    final pages = context.watch<WebPagesCubit>().state.pages;

    return _WebNavSection(
      section: NavSection.webPages,
      icon: icon,
      label: appLocalizationsOf(context).webPages,
      showLabel: showLabel,
      isCurrent: router.showingWebPages,
      onOpen: () {
        _closeDrawer(context);
        router.showWebPages();
      },
      items: [
        for (final page in pages)
          DriveNavRow(
            icon: null,
            dense: true,
            label: page.title,
            onTap: () {
              _closeDrawer(context);
              openWebPageFolder(context, page);
            },
          ),
      ],
    );
  }
}

/// Names: the linked wallet's ArNS names, bare (`maya`, not `maya.ar.io`),
/// with a red dot on one whose lease ends soon.
class NamesNavHeading extends StatelessWidget {
  const NamesNavHeading({super.key, required this.showLabel});

  final bool showLabel;

  static const icon = ArDriveIconsData.arns_name;

  @override
  Widget build(BuildContext context) {
    final router = context.watch<AppRouterDelegate>();
    final strings = appLocalizationsOf(context);
    final now = DateTime.now();
    final names = context
        .watch<ArNSNamesCubit>()
        .state
        .names
        .where((n) => !n.isExpired(now))
        .toList();

    return _WebNavSection(
      section: NavSection.names,
      icon: icon,
      label: strings.arnsNames,
      showLabel: showLabel,
      isCurrent: router.showingNames && router.shownName == null,
      onOpen: () {
        _closeDrawer(context);
        router.showNames();
      },
      items: [
        for (final name in names)
          DriveNavRow(
            icon: null,
            dense: true,
            label: name.name,
            isCurrent: router.showingNames && router.shownName == name.name,
            trailing: _renewalDot(context, name, now),
            onTap: () {
              _closeDrawer(context);
              router.showNames(name: name.name);
            },
          ),
      ],
    );
  }

  /// The lease ends within [arnsRenewalNoticeWindow], or has ended and is
  /// in its grace period: the name is about to be lost.
  Widget? _renewalDot(
      BuildContext context, ArNSManagedName name, DateTime now) {
    final end = name.endTimestamp;
    if (end == null || end.difference(now) > arnsRenewalNoticeWindow) {
      return null;
    }
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final days = end.difference(now).inDays.clamp(0, 30);
    // In its grace period the lease has ended, as the Names table says.
    final text = name.isInGracePeriod(now)
        ? appLocalizationsOf(context).arnsLeaseHasEnded
        : appLocalizationsOf(context).arnsLeaseEndsInDays(days);
    return ArDriveTooltip(
      message: text,
      child: Semantics(
        label: text,
        child: Container(
          key: const ValueKey('arns-renewal-dot'),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: colorTokens.statusErrorFg,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

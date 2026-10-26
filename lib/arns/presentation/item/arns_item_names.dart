import 'package:ardrive/arns/data/arns_name_verifier.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/widgets/arns_widgets.dart';
import 'package:ardrive/components/dotted_line.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Whether names are on in this app: the flag, outside a publication, with
/// the names cubit provided.
bool arnsNamesOn(BuildContext context) {
  if (PublicationMode.isOn) return false;
  try {
    if (!context.read<ConfigService>().config.enableArNS) return false;
    context.read<ArNSNamesCubit>();
    return true;
  } on ProviderNotFoundException {
    return false;
  }
}

/// The item as something to name, when it can be named here: the owner's
/// file in a public drive, deployments included (docs/NAMES.md, Q5).
ArNSNameableItem? arnsNameableItem(
  BuildContext context, {
  required ArDriveDataTableItem item,
  required Drive? drive,
}) {
  if (item is! FileDataTableItem || drive == null) return null;
  if (!isArNSNameable(
    namesEnabled: arnsNamesOn(context),
    driveIsPublic: drive.isPublic,
    isOwner: item.isOwner,
  )) {
    return null;
  }
  return ArNSNameableItem(
    fileId: item.id,
    driveId: item.driveId,
    name: item.name,
    dataTxId: item.dataTxId,
    isManifest: item.contentType == ContentType.manifest,
  );
}

/// Add name, or Change name and Remove name, for an item's menu (Q21).
List<ArDriveDropdownItem> arnsItemMenuItems(
  BuildContext context, {
  required ArDriveDataTableItem item,
  required Drive? drive,
  double? height,
}) {
  final nameable = arnsNameableItem(context, item: item, drive: drive);
  if (nameable == null) return const [];
  final strings = appLocalizationsOf(context);
  final records =
      context.read<ArNSNamesCubit>().state.recordsFor(nameable.dataTxId);

  ArDriveDropdownItem entry(String label, IconData icon, VoidCallback onTap) =>
      ArDriveDropdownItem(
        onClick: onTap,
        content: ArDriveDropdownItemTile(
          name: label,
          // The menu's own size: at 24 the icon and label sat 4 px right
          // of every other item's.
          icon: ArDriveIcon(icon: icon, size: defaultIconSize),
          height: height,
        ),
      );

  if (records.isEmpty) {
    return [
      entry(
        strings.arnsAddName,
        arnsNameIcon,
        () => showArNSNameDialog(
          context,
          mode: ArNSNameDialogMode.nameItem,
          item: nameable,
        ),
      ),
    ];
  }
  return [
    entry(
      strings.arnsChangeName,
      arnsNameIcon,
      () => showArNSNameDialog(
        context,
        mode: ArNSNameDialogMode.nameItem,
        item: nameable,
      ),
    ),
    entry(
      strings.arnsRemoveName,
      Icons.link_off,
      () => promptToRemoveArNSName(
        context,
        item: nameable,
        record: records.first,
      ),
    ),
  ];
}

Future<void> promptToRemoveArNSName(
  BuildContext context, {
  required ArNSNameRecord record,
  ArNSNameableItem? item,
}) =>
    showArNSNameDialog(
      context,
      mode: ArNSNameDialogMode.remove,
      item: item,
      choice: ArNSRecordChoice(name: record.name, undername: record.undername),
    );

/// A small globe with the item's name, on explorer rows (Q14). The owner's
/// own names come from ArNS; anyone else's from the file's metadata, shown
/// only once the gateway confirms them ([ArNSNameVerifier]).
class ArNSNameChip extends StatelessWidget {
  const ArNSNameChip({
    super.key,
    required this.dataTxId,
    this.hints = const [],
    this.isOwner = true,
    this.iconOnly = false,
  });

  final String dataTxId;

  /// The file's `assignedNames`, for a visitor.
  final List<String> hints;
  final bool isOwner;

  /// Just the globe, the names in its tooltip: where a row has no room for
  /// the name beside its title ([ArNSRowTitle]).
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    if (arnsNamesOn(context)) {
      return BlocBuilder<ArNSNamesCubit, ArNSNamesState>(
        buildWhen: (a, b) => a.names != b.names,
        builder: (context, state) {
          final records = state.recordsFor(dataTxId);
          if (records.isNotEmpty) {
            return _NameChipView(
              iconOnly: iconOnly,
              names: [for (final r in records) r.literalName],
            );
          }
          return isOwner ? const SizedBox.shrink() : _verified(context);
        },
      );
    }
    return _verified(context);
  }

  Widget _verified(BuildContext context) {
    if (hints.isEmpty) return const SizedBox.shrink();
    final verifier = arnsVisitorVerifier(context);
    if (verifier == null) return const SizedBox.shrink();
    // Never blocks the row: it draws without a chip until confirmed.
    return ArNSConfirmedNames(
      verifier: verifier,
      hints: hints,
      dataTxIds: {dataTxId},
      builder: (context, names) =>
          names.isEmpty ? const SizedBox.shrink() : _NameChipView(names: names),
    );
  }
}

/// Builds with the names in [hints] the gateway confirms, empty until then.
/// Asks once per set of hints, however often its parent rebuilds: a new
/// future on each build left the answer waiting for good.
class ArNSConfirmedNames extends StatefulWidget {
  const ArNSConfirmedNames({
    super.key,
    required this.verifier,
    required this.hints,
    required this.dataTxIds,
    required this.builder,
  });

  final ArNSNameVerifier verifier;
  final List<String> hints;
  final Set<String> dataTxIds;
  final Widget Function(BuildContext context, List<String> names) builder;

  @override
  State<ArNSConfirmedNames> createState() => _ArNSConfirmedNamesState();
}

class _ArNSConfirmedNamesState extends State<ArNSConfirmedNames> {
  late Future<List<String>> _names = _ask();

  Future<List<String>> _ask() =>
      arnsConfirmedNames(widget.verifier, widget.hints, widget.dataTxIds);

  @override
  void didUpdateWidget(ArNSConfirmedNames old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.hints, widget.hints) ||
        !setEquals(old.dataTxIds, widget.dataTxIds)) {
      _names = _ask();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
        future: _names,
        builder: (context, snapshot) =>
            widget.builder(context, snapshot.data ?? const []),
      );
}

/// The names in [hints] the gateway resolves to one of [dataTxIds]: what a
/// visitor may see of a file's `assignedNames` (docs/NAMES.md, "Visitors").
Future<List<String>> arnsConfirmedNames(
  ArNSNameVerifier verifier,
  List<String> hints,
  Set<String> dataTxIds,
) async {
  final resolved = await Future.wait([
    for (final name in hints) verifier.resolve(name),
  ]);
  return [
    for (var i = 0; i < hints.length; i++)
      if (resolved[i] != null && dataTxIds.contains(resolved[i])) hints[i],
  ];
}

/// An Activity entry for a name change. The owner sees the name the
/// revision wrote; anyone else sees it only once the gateway confirms it
/// still points at the file, and otherwise a plain "modified" line (Q6).
class ArNSNameActivity extends StatelessWidget {
  const ArNSNameActivity({
    super.key,
    required this.names,
    required this.dataTxIds,
    required this.isOwner,
    required this.builder,
  });

  /// The revision's `assignedNames`.
  final List<String> names;

  /// The file's data, this revision's and its latest.
  final Set<String> dataTxIds;
  final bool isOwner;
  final Widget Function(BuildContext context, String title) builder;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    if (names.isEmpty) {
      return builder(context, strings.arnsActivityNameRemoved);
    }
    if (isOwner) {
      return builder(
        context,
        strings.arnsActivityNameAssigned(arnsHostFor(names.last)),
      );
    }
    final verifier = arnsVisitorVerifier(context);
    if (verifier == null) return builder(context, strings.fileWasModified);
    return ArNSConfirmedNames(
      verifier: verifier,
      hints: names,
      dataTxIds: dataTxIds,
      builder: (context, confirmed) => builder(
        context,
        confirmed.isEmpty
            ? strings.fileWasModified
            : strings.arnsActivityNameAssigned(arnsHostFor(confirmed.last)),
      ),
    );
  }
}

/// The session's name verifier, while names are on (publication pages
/// included, where visitors see names).
ArNSNameVerifier? arnsVisitorVerifier(BuildContext context) {
  try {
    final config = context.read<ConfigService>();
    if (!config.config.enableArNS) return null;
    return ArNSNameVerifier.session ??= ArNSNameVerifier(
      gatewayUrl: () => config.config.arweaveGatewayForDataRequest.url,
    );
  } on ProviderNotFoundException {
    return null;
  }
}

/// An item's title with its name chip: beside the title while both fit,
/// under it when they don't. In a row, the chip kept its width and the
/// title was left a few letters wide on a phone.
class ArNSTitleWithChip extends StatelessWidget {
  const ArNSTitleWithChip({
    super.key,
    required this.title,
    required this.chip,
  });

  final Widget title;
  final Widget chip;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: ArDriveSpacing.xxs,
      children: [title, chip],
    );
  }
}

/// A row's title with its name chip beside it, the title first: the chip
/// takes only the room the whole title leaves, ellipsized down to
/// [minWidth], then just the globe, then nothing. With the details panel
/// open, the chip kept its width and the file name was cut to "e2e-name-1.t…".
class ArNSRowTitle extends StatelessWidget {
  const ArNSRowTitle({
    super.key,
    required this.text,
    required this.style,
    required this.title,
    required this.chip,
  });

  /// The title as drawn, to measure it.
  final String text;
  final TextStyle style;

  /// The title widget: [text] in [style], ellipsized.
  final Widget title;
  final ArNSNameChip Function(bool iconOnly) chip;

  /// The narrowest chip that still shows a few letters of the name.
  static const minWidth = 72.0;

  /// The globe alone, with its start padding.
  static const iconOnlyWidth = 36.0;

  /// The widest the chip gets.
  static const maxWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          // As the Text draws it: its style over the inherited one.
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final room = constraints.maxWidth - painter.width.ceilToDouble();
        painter.dispose();
        return Row(
          children: [
            Flexible(child: title),
            if (room >= iconOnlyWidth)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: room.clamp(0, maxWidth)),
                child: chip(room < minWidth),
              ),
          ],
        );
      },
    );
  }
}

class _NameChipView extends StatelessWidget {
  const _NameChipView({required this.names, this.iconOnly = false});

  final List<String> names;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final host = arnsHostFor(names.first);
    final more = names.length - 1;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: ArDriveSpacing.xs),
      child: ArDriveTooltip(
        message: names.map(arnsHostFor).join('\n'),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: ArDriveSpacing.xs,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: colors.containerL2,
            borderRadius: BorderRadius.circular(ArDriveRadius.lg),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(arnsNameIcon, size: 12, color: colors.iconMid),
              if (!iconOnly) ...[
                const SizedBox(width: ArDriveSpacing.xxs),
                Flexible(
                  child: Text(
                    more > 0 ? '$host +$more' : host,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    softWrap: false,
                    style: typography.caption(
                      color: colors.textMid,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The details panel's Name section: the name, Copy link, Change, Remove.
class ArNSNameSection extends StatelessWidget {
  const ArNSNameSection({super.key, required this.item});

  final ArNSNameableItem item;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return BlocBuilder<ArNSNamesCubit, ArNSNamesState>(
      builder: (context, state) {
        final records = state.recordsFor(item.dataTxId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.arnsName,
              style: typography.paragraphNormal(fontWeight: ArFontWeight.bold),
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            if (records.isEmpty)
              Row(
                children: [
                  Expanded(child: ArNSCaption(strings.arnsNoNameYet)),
                  ArDriveButtonNew(
                    text: strings.arnsAddName,
                    typography: typography,
                    size: ArDriveButtonSize.compact,
                    variant: ButtonVariant.secondary,
                    onPressed: () => showArNSNameDialog(
                      context,
                      mode: ArNSNameDialogMode.nameItem,
                      item: item,
                    ),
                  ),
                ],
              )
            else
              for (final record in records) ...[
                _NameLink(literal: record.literalName),
                const SizedBox(height: ArDriveSpacing.xxs),
                Wrap(
                  spacing: ArDriveSpacing.md,
                  runSpacing: ArDriveSpacing.xxs,
                  children: [
                    _CopyNameLink(literal: record.literalName),
                    ArDriveLink(
                      text: strings.arnsChange,
                      isAction: true,
                      onTap: () => showArNSNameDialog(
                        context,
                        mode: ArNSNameDialogMode.nameItem,
                        item: item,
                      ),
                    ),
                    ArDriveLink(
                      text: strings.arnsRemove,
                      isAction: true,
                      onTap: () => promptToRemoveArNSName(
                        context,
                        item: item,
                        record: record,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ArDriveSpacing.xs),
              ],
            const SizedBox(height: 10),
            HorizontalDottedLine(
              color: colors.strokeLow,
              width: double.maxFinite,
            ),
          ],
        );
      },
    );
  }
}

/// A name as a link that opens it, with the globe.
class _NameLink extends StatelessWidget {
  const _NameLink({required this.literal});

  final String literal;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Row(
      children: [
        Icon(arnsNameIcon, size: 16, color: colors.iconMid),
        const SizedBox(width: ArDriveSpacing.xs),
        Expanded(
          child: ArDriveLink(
            text: arnsHostFor(literal),
            external: true,
            onTap: () => openUrl(url: arnsUrlFor(literal)),
          ),
        ),
      ],
    );
  }
}

class _CopyNameLink extends StatelessWidget {
  const _CopyNameLink({required this.literal});

  final String literal;

  @override
  Widget build(BuildContext context) => ArDriveLink(
        text: appLocalizationsOf(context).copyLink,
        isAction: true,
        onTap: () =>
            Clipboard.setData(ClipboardData(text: arnsUrlFor(literal))),
      );
}

/// The details panel's Name section for someone else's file: its names
/// once the gateway confirms them, to open or copy, and nothing to manage
/// (Q6, Q14). Draws nothing until then, or when none is confirmed.
class ArNSVisitorNameSection extends StatelessWidget {
  const ArNSVisitorNameSection({
    super.key,
    required this.dataTxId,
    required this.hints,
  });

  final String dataTxId;

  /// The file's `assignedNames`.
  final List<String> hints;

  @override
  Widget build(BuildContext context) {
    if (hints.isEmpty) return const SizedBox.shrink();
    final verifier = arnsVisitorVerifier(context);
    if (verifier == null) return const SizedBox.shrink();
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return ArNSConfirmedNames(
      verifier: verifier,
      hints: hints,
      dataTxIds: {dataTxId},
      builder: (context, names) {
        if (names.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: ArDriveSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.arnsName,
                style:
                    typography.paragraphNormal(fontWeight: ArFontWeight.bold),
              ),
              const SizedBox(height: ArDriveSpacing.xs),
              for (final literal in names) ...[
                _NameLink(literal: literal),
                const SizedBox(height: ArDriveSpacing.xxs),
                _CopyNameLink(literal: literal),
                const SizedBox(height: ArDriveSpacing.xs),
              ],
              const SizedBox(height: 10),
              HorizontalDottedLine(
                color: colors.strokeLow,
                width: double.maxFinite,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// After a named file is hidden: offer to remove its name, since hiding is
/// the only way an item leaves public view (docs/NAMES.md, "Removing").
Future<void> offerToRemoveArNSNameAfterHide(
  BuildContext context, {
  required ArNSNameableItem item,
}) async {
  if (!arnsNamesOn(context)) return;
  final records =
      context.read<ArNSNamesCubit>().state.recordsFor(item.dataTxId);
  if (records.isEmpty) return;
  final strings = appLocalizationsOf(context);
  final record = records.first;
  final remove = await showArDriveDialogWithBuilder<bool>(
    context,
    builder: (dialogContext) => ArDriveStandardModalNew(
      title: strings.arnsRemoveNameTooTitle,
      description: strings.arnsRemoveNameTooBody(
        arnsHostFor(record.literalName),
      ),
      actions: [
        ModalAction.dismiss(
          title: strings.arnsKeepName,
          action: () => Navigator.of(dialogContext).pop(false),
        ),
        ModalAction(
          title: strings.arnsRemoveName,
          action: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  if (remove == true && context.mounted) {
    await promptToRemoveArNSName(context, item: item, record: record);
  }
}

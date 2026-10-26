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
import 'package:ardrive_ui/ardrive_ui.dart';
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
          icon: ArDriveIcon(icon: icon, size: 24),
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

/// A small globe with the item's name, on explorer rows (Q14).
class ArNSNameChip extends StatelessWidget {
  const ArNSNameChip({super.key, required this.dataTxId});

  final String dataTxId;

  @override
  Widget build(BuildContext context) {
    if (!arnsNamesOn(context)) return const SizedBox.shrink();
    return BlocBuilder<ArNSNamesCubit, ArNSNamesState>(
      buildWhen: (a, b) => a.names != b.names,
      builder: (context, state) {
        final records = state.recordsFor(dataTxId);
        if (records.isEmpty) return const SizedBox.shrink();
        final colors = ArDriveTheme.of(context).themeData.colorTokens;
        final typography = ArDriveTypographyNew.of(context);
        final host = arnsHostFor(records.first.literalName);
        final more = records.length - 1;
        return Padding(
          padding: const EdgeInsetsDirectional.only(start: ArDriveSpacing.xs),
          child: ArDriveTooltip(
            message: records.map((r) => arnsHostFor(r.literalName)).join('\n'),
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
              ),
            ),
          ),
        );
      },
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
                Row(
                  children: [
                    Icon(arnsNameIcon, size: 16, color: colors.iconMid),
                    const SizedBox(width: ArDriveSpacing.xs),
                    Expanded(
                      child: ArDriveLink(
                        text: arnsHostFor(record.literalName),
                        external: true,
                        onTap: () =>
                            openUrl(url: arnsUrlFor(record.literalName)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ArDriveSpacing.xxs),
                Wrap(
                  spacing: ArDriveSpacing.md,
                  runSpacing: ArDriveSpacing.xxs,
                  children: [
                    ArDriveLink(
                      text: strings.copyLink,
                      isAction: true,
                      onTap: () => Clipboard.setData(ClipboardData(
                        text: arnsUrlFor(record.literalName),
                      )),
                    ),
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

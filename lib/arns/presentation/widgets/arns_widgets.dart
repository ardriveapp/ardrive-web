import 'package:ardrive/arns/domain/arns_cache_time.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The icon that stands for a name, beside the name as text: ArNS's own, as
/// in the left nav's Names entry. The globe is for public drives.
const arnsNameIcon = ArDriveIconsData.arns_name;

class ArNSBodyText extends StatelessWidget {
  const ArNSBodyText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: ArDriveTypographyNew.of(context).paragraphNormal(
          color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
        ),
      );
}

class ArNSCaption extends StatelessWidget {
  const ArNSCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: ArDriveTypographyNew.of(context).paragraphSmall(
          color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
        ),
      );
}

/// A spinner and what is being waited for.
class ArNSWaitingLine extends StatelessWidget {
  const ArNSWaitingLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ArDriveSpinner(),
        const SizedBox(width: ArDriveSpacing.sm),
        Expanded(child: ArNSCaption(text)),
      ],
    );
  }
}

/// A wallet with no names: where to get one.
class ArNSNoNames extends StatelessWidget {
  const ArNSNoNames({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveEmptyState(
      icon: Icon(arnsNameIcon, size: 32, color: colors.iconLow),
      title: strings.arnsNoNamesTitle,
      message: strings.arnsNoNamesBody,
      actionLabel: strings.arnsGetANameInConsole,
      onAction: () => openUrl(url: arnsConsoleUrl),
    );
  }
}

/// One choice in a list: a name, an undername, an item.
class ArNSChoiceRow extends StatelessWidget {
  const ArNSChoiceRow({
    super.key,
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.tag,
    this.enabled = true,
    this.indent = false,
    this.emphasized = false,
    this.leadingIcon,
  });

  final bool selected;
  final String title;
  final String? subtitle;

  /// A quiet label at the end, such as "Managed for its owner".
  final String? tag;
  final bool enabled;
  final bool indent;
  final bool emphasized;
  final IconData? leadingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final fg = enabled ? colors.textHigh : colors.textLow;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      button: true,
      child: Material(
        color: selected ? colors.containerL2 : Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                indent ? ArDriveSpacing.md + 28 : ArDriveSpacing.md,
                ArDriveSpacing.xs,
                ArDriveSpacing.md,
                ArDriveSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    leadingIcon ??
                        (selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                    size: 20,
                    color: selected
                        ? colors.iconHigh
                        : (enabled ? colors.iconMid : colors.iconLow),
                  ),
                  const SizedBox(width: ArDriveSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: typography.paragraphNormal(
                            color: fg,
                            fontWeight: emphasized || selected
                                ? ArFontWeight.bold
                                : ArFontWeight.semiBold,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            overflow: TextOverflow.ellipsis,
                            style: typography.paragraphSmall(
                              color: colors.textLow,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (tag != null) ...[
                    const SizedBox(width: ArDriveSpacing.xs),
                    ArNSTag(text: tag!),
                  ],
                  if (leadingIcon != null && selected) ...[
                    const SizedBox(width: ArDriveSpacing.xs),
                    Icon(Icons.check, size: 18, color: colors.iconHigh),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small quiet label: "Managed for its owner", "Renews in 12 days".
class ArNSTag extends StatelessWidget {
  const ArNSTag({super.key, required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ArDriveSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: warning ? colors.statusWarningContainer : colors.containerL2,
        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
        border: warning ? Border.all(color: colors.statusWarningStroke) : null,
      ),
      child: Text(
        text,
        style: typography.caption(
          color: colors.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
      ),
    );
  }
}

String arnsCacheTimeLabel(BuildContext context, ArNSCacheTime time) {
  final strings = appLocalizationsOf(context);
  return switch (time) {
    ArNSCacheTime.oneMinute => strings.arnsCacheTime1Min,
    ArNSCacheTime.fiveMinutes => strings.arnsCacheTime5Min,
    ArNSCacheTime.fifteenMinutes => strings.arnsCacheTime15Min,
    ArNSCacheTime.oneHour => strings.arnsCacheTime1Hour,
    ArNSCacheTime.oneDay => strings.arnsCacheTime1Day,
  };
}

/// A record's cache time as said: "5 min", or the seconds when it was set
/// elsewhere to a time ArDrive doesn't offer.
String arnsTtlLabel(BuildContext context, int seconds) {
  final known = ArNSCacheTime.fromSeconds(seconds);
  if (known != null) return arnsCacheTimeLabel(context, known);
  return appLocalizationsOf(context).arnsCacheTimeSeconds(seconds);
}

/// Cache time: 1 min, 5 min, 15 min, 1 hour, 1 day, with its trade-off.
class ArNSCacheTimePicker extends StatelessWidget {
  const ArNSCacheTimePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ArNSCacheTime value;
  final ValueChanged<ArNSCacheTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.arnsCacheTime,
          style: typography.paragraphNormal(
            color: colors.textHigh,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
        const SizedBox(height: ArDriveSpacing.xs),
        Wrap(
          spacing: ArDriveSpacing.xs,
          runSpacing: ArDriveSpacing.xs,
          children: [
            for (final time in ArNSCacheTime.values)
              _CacheTimeOption(
                label: arnsCacheTimeLabel(context, time),
                selected: time == value,
                onTap: () => onChanged(time),
              ),
          ],
        ),
        const SizedBox(height: ArDriveSpacing.xs),
        ArNSCaption(strings.arnsCacheTimeTradeOff),
      ],
    );
  }
}

class _CacheTimeOption extends StatelessWidget {
  const _CacheTimeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? colors.containerL3 : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArDriveRadius.lg * 2),
          side: BorderSide(
            color: selected ? colors.strokeHigh : colors.strokeLow,
          ),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ArDriveRadius.lg * 2),
          ),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: ArDriveSpacing.sm),
            alignment: Alignment.center,
            child: Text(
              label,
              style: typography.paragraphNormal(
                color: selected ? colors.textHigh : colors.textMid,
                fontWeight:
                    selected ? ArFontWeight.bold : ArFontWeight.semiBold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Cost" and its value, with what it covers.
class ArNSCostRow extends StatelessWidget {
  const ArNSCostRow({
    super.key,
    required this.label,
    required this.value,
    this.note,
  });

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return Container(
      padding: const EdgeInsets.all(ArDriveSpacing.sm),
      decoration: BoxDecoration(
        color: colors.containerL1,
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: typography.paragraphNormal(color: colors.textMid),
                ),
              ),
              Text(
                value,
                style: typography.paragraphNormal(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.bold,
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: ArDriveSpacing.xxs),
            Text(
              note!,
              style: typography.paragraphSmall(color: colors.textLow),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Switch to 7xKp…q2Fd in your wallet, or change your ArNS wallet."
class ArNSSwitchAccountText extends StatelessWidget {
  const ArNSSwitchAccountText({super.key, required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final short = shortArNSAddress(address);
    final sentence = appLocalizationsOf(context).arnsSwitchAccount(short);
    return Text.rich(
      TextSpan(
        style: typography.paragraphNormal(color: colors.textHigh),
        children: ArDriveIdText.spansIn(
          sentence,
          short,
          idStyle: typography.code(color: colors.textHigh),
        ),
      ),
    );
  }
}

/// `7xKp...q2Fd`.
String shortArNSAddress(String address) => address.length <= 10
    ? address
    : truncateString(address, offsetStart: 4, offsetEnd: 4);

/// What a record points to, as text: the item's name, "Nothing published
/// here", or "Points elsewhere".
String arnsPointsToLabel(
  BuildContext context,
  ArNSNameRecord record, {
  String? placeholder,
}) {
  final strings = appLocalizationsOf(context);
  final name = switch (record.target) {
    ArNSFileItem(:final name) => name,
    _ => '',
  };
  return switch (arnsPointsToKind(record, placeholder: placeholder)) {
    ArNSPointsToKind.nothingPublished => strings.arnsNothingPublished,
    ArNSPointsToKind.file => strings.arnsPointsToItem(name),
    ArNSPointsToKind.olderVersion => strings.arnsPointsToOlderVersion(name),
    ArNSPointsToKind.publication => strings.arnsPointsToPublication,
    ArNSPointsToKind.elsewhere => strings.arnsPointsElsewhere,
  };
}

/// "Points to" with the item, or "Points elsewhere" (Q22). The transaction
/// it points to is in the tooltip, not the row: it means nothing to most
/// people, and nothing here acts on it.
class ArNSPointsTo extends StatelessWidget {
  const ArNSPointsTo({super.key, required this.record, this.placeholder});

  final ArNSNameRecord record;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final label = arnsPointsToLabel(context, record, placeholder: placeholder);
    final text = Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: typography.paragraphSmall(color: colors.textMid),
    );
    if (arnsPointsToKind(record, placeholder: placeholder) !=
        ArNSPointsToKind.elsewhere) {
      return text;
    }
    return ArDriveTooltip(message: record.transactionId, child: text);
  }
}

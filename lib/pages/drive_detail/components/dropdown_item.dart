import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ArDriveArDriveDropdownItemTileIconAlignment {
  left,
  right,
}

class ArDriveDropdownItemTile extends StatelessWidget {
  final String name;
  final ArDriveIcon? icon;
  final bool isDisabled;
  final TextStyle? fontStyle;
  final ArDriveArDriveDropdownItemTileIconAlignment iconAlignment;
  final double? height;

  /// A second, smaller line under [name] saying what the item does. The menu
  /// sizes its items from [height] and does not measure them, so a tile with
  /// one needs a [height] with room for it, and its menu a matching
  /// `maxHeight`; see [describedDropdownItemHeight].
  final String? description;

  const ArDriveDropdownItemTile({
    super.key,
    required this.name,
    this.icon,
    this.isDisabled = false,
    this.fontStyle,
    this.iconAlignment = ArDriveArDriveDropdownItemTileIconAlignment.left,
    this.height,
    this.description,
  });

  TextStyle _nameStyle(BuildContext context) =>
      fontStyle ??
      ArDriveTypographyNew.of(context).paragraphNormal(
        color: _labelColor(context),
        fontWeight: ArFontWeight.semiBold,
      );

  Color _labelColor(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return isDisabled ? colorTokens.textXLow : colorTokens.textHigh;
  }

  /// The icon in the label's colour, unless it was given one of its own (a
  /// red delete, say). A disabled item greys it either way.
  ArDriveIcon _icon(BuildContext context) => icon!.copyWith(
        color: isDisabled
            ? ArDriveTheme.of(context).themeData.colorTokens.textXLow
            : icon!.color ?? _labelColor(context),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ArDriveSpacing.md),
      child: SizedBox(
        // Scaled: the row is a fixed 48 at scale 1, and a label at text scale
        // 2 needs twice the line box. Without this the label is squeezed
        // instead of the row growing, and "Sync history" - the only door to
        // the history - reads as a cut-off word on a 320px phone.
        height: (height ?? 48) *
            MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (icon != null &&
                iconAlignment ==
                    ArDriveArDriveDropdownItemTileIconAlignment.left) ...[
              _icon(context),
              const SizedBox(width: ArDriveSpacing.md),
            ],
            // Flexible, and allowed to ellipsize. The row is `MainAxisSize.max`
            // inside a menu whose width is the screen's on a phone, so a label
            // that insisted on its full width overflowed it: at 320px and text
            // scale 2.0, "Deep Resync" ran 58 pixels past the right edge of
            // every menu in the app, with no way for the label to give.
            Flexible(
              child: description == null
                  ? Text(
                      name,
                      // Two lines, into the height the row now grows to. One
                      // line ellipsized the label instead of using that room,
                      // so at 320px and text scale 2.0 a command read as a
                      // cut-off word - and "Sync history" is the only way into
                      // the record.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _nameStyle(context),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _nameStyle(context),
                        ),
                        const SizedBox(height: 2),
                        // Capped, because the menu is as wide as its widest
                        // item: unwrapped, a sentence would stretch it across
                        // the screen.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                ArDriveTypographyNew.of(context).paragraphSmall(
                              color: isDisabled
                                  ? ArDriveTheme.of(context)
                                      .themeData
                                      .colorTokens
                                      .textXLow
                                  : ArDriveTheme.of(context)
                                      .themeData
                                      .colorTokens
                                      .textMid,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (icon != null &&
                iconAlignment ==
                    ArDriveArDriveDropdownItemTileIconAlignment.right) ...[
              const Spacer(),
              _icon(context),
            ]
          ],
        ),
      ),
    );
  }
}

/// The [ArDriveDropdownItemTile.height] for a tile with a description: room
/// for its name and two lines under it, before text scaling, which the tile
/// and the menu both apply.
const double describedDropdownItemHeight = 72;

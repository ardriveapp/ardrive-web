import 'package:ardrive/blocs/fs_entry_snapshots/models/snapshot_display_item.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/components/dotted_line.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Displays a single snapshot item in the snapshots list.
class SnapshotListItem extends StatelessWidget {
  final SnapshotDisplayItem snapshot;

  const SnapshotListItem({
    super.key,
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colors;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with status dot and date as title
        Row(
          children: [
            // Status indicator dot with tooltip
            _buildStatusDot(context, colors, colorTokens),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                formatDateToUtcString(snapshot.createdAt),
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                ),
              ),
            ),
            // Block range info icon with tooltip
            ArDriveTooltip(
              message: appLocalizationsOf(context).blockRangeTooltip(
                snapshot.blockStart.toString(),
                snapshot.blockEnd.toString(),
              ),
              child: ArDriveIcons.info(
                size: 16,
                color: colorTokens.textLow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Transaction ID
        _buildInfoRow(
          context,
          typography,
          appLocalizationsOf(context).transactionId,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (snapshot.isConfirmed)
                ArDriveClickArea(
                  child: GestureDetector(
                    onTap: () {
                      openUrl(
                        url: 'https://viewblock.io/arweave/tx/${snapshot.txId}',
                      );
                    },
                    child: ArDriveTooltip(
                      message: snapshot.txId,
                      child: Text(
                        truncateString(
                          snapshot.txId,
                          offsetStart: 4,
                          offsetEnd: 4,
                        ),
                        style: typography.paragraphNormal().copyWith(
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ),
                  ),
                )
              else
                ArDriveTooltip(
                  message: snapshot.txId,
                  child: Text(
                    truncateString(
                      snapshot.txId,
                      offsetStart: 4,
                      offsetEnd: 4,
                    ),
                    style: typography.paragraphNormal(),
                  ),
                ),
              const SizedBox(width: 8),
              CopyButton(text: snapshot.txId),
            ],
          ),
        ),
        const SizedBox(height: 16),

        HorizontalDottedLine(
          color: ArDriveTheme.of(context).themeData.colors.themeBorderDefault,
          width: double.maxFinite,
        ),
      ],
    );
  }

  /// Builds a colored status dot indicator with tooltip (same pattern as file status).
  Widget _buildStatusDot(
    BuildContext context,
    ArDriveColors colors,
    ArDriveColorTokens colorTokens,
  ) {
    Color indicatorColor;
    String? tooltipMessage;

    if (snapshot.isPending) {
      indicatorColor = colors.themeWarningFg;
      tooltipMessage = appLocalizationsOf(context).snapshotPendingTooltip;
    } else if (snapshot.isConfirmed) {
      indicatorColor = colors.themeSuccessFb;
      tooltipMessage = appLocalizationsOf(context).snapshotConfirmedTooltip;
    } else if (snapshot.isFailed) {
      indicatorColor = colors.themeErrorFg;
      tooltipMessage = appLocalizationsOf(context).snapshotFailedTooltip;
    } else {
      indicatorColor = Colors.transparent;
    }

    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: indicatorColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    if (tooltipMessage != null) {
      return ArDriveTooltip(
        message: tooltipMessage,
        child: dot,
      );
    }

    return dot;
  }

  Widget _buildInfoRow(
    BuildContext context,
    ArdriveTypographyNew typography,
    String label,
    Widget value,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.bold,
          ),
        ),
        value,
      ],
    );
  }
}

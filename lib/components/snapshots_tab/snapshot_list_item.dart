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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with status dot and title
        Row(
          children: [
            // Status indicator dot (same as files)
            _buildStatusDot(context, colors),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                appLocalizationsOf(context).snapshot,
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Created date
        _buildInfoRow(
          context,
          typography,
          appLocalizationsOf(context).dateCreated,
          Text(
            formatDateToUtcString(snapshot.createdAt),
            style: typography.paragraphNormal(),
          ),
        ),
        const SizedBox(height: 8),

        // Block range
        _buildInfoRow(
          context,
          typography,
          appLocalizationsOf(context).blockRange,
          Text(
            '${snapshot.blockStart} - ${snapshot.blockEnd}',
            style: typography.paragraphNormal(),
          ),
        ),
        const SizedBox(height: 8),

        // Transaction ID
        _buildInfoRow(
          context,
          typography,
          appLocalizationsOf(context).transactionId,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (snapshot.isConfirmed) ...[
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
                ),
                const SizedBox(width: 8),
              ],
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

  /// Builds a colored status dot indicator (same pattern as file status).
  Widget _buildStatusDot(BuildContext context, ArDriveColors colors) {
    Color indicatorColor;

    if (snapshot.isPending) {
      indicatorColor = colors.themeWarningFg;
    } else if (snapshot.isConfirmed) {
      indicatorColor = colors.themeSuccessFb;
    } else if (snapshot.isFailed) {
      indicatorColor = colors.themeErrorFg;
    } else {
      indicatorColor = Colors.transparent;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: indicatorColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );
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

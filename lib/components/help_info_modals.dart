import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Shows a modal with licensing information
Future<void> showLicensingInfoModal({
  required BuildContext context,
}) async {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final l10n = appLocalizationsOf(context);

  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      title: l10n.licensingInfoTitle,
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.licensingInfoIntro,
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            Text(
              l10n.licensingInfoOptions,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.sm),
            _buildBulletPoint(
              context,
              'Universal Data License (UDL)',
              l10n.licensingInfoUdl,
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            _buildBulletPoint(
              context,
              'Creative Commons',
              l10n.licensingInfoCreativeCommons,
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            ArDriveNotice(
              type: ArDriveNoticeType.info,
              message: l10n.licensingInfoNotice,
            ),
          ],
        ),
      ),
      actions: [
        ModalAction.close(
          title: l10n.close,
          action: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// Shows a modal explaining keyfile and seed phrase login
Future<void> showKeyfileInfoModal({
  required BuildContext context,
}) async {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final l10n = appLocalizationsOf(context);

  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      title: l10n.keyfileInfoTitle,
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.keyfileInfoKeyfiles,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            Text(
              l10n.keyfileInfoKeyfilesBody,
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.md),
            Text(
              l10n.keyfileInfoSeedPhrases,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            Text(
              l10n.keyfileInfoSeedPhrasesBody,
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            ArDriveNotice(
              type: ArDriveNoticeType.warning,
              message: l10n.keyfileInfoWarning,
            ),
          ],
        ),
      ),
      actions: [
        ModalAction.close(
          title: l10n.close,
          action: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// Shows a modal with ArDrive app limits
Future<void> showAppLimitsInfoModal({
  required BuildContext context,
}) async {
  // Redirect to the new Turbo info modal which includes limits
  return showTurboInfoModal(context: context);
}

/// Shows a modal explaining Turbo and its benefits
Future<void> showTurboInfoModal({
  required BuildContext context,
}) async {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  await showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      hasCloseButton: true,
      title: 'About Turbo',
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // What is Turbo
              Text(
                'Turbo is the fastest, most reliable way to upload data to Arweave.',
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
              const SizedBox(height: 20),

              // Benefits
              Text(
                'Benefits',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                  color: colorTokens.textHigh,
                ),
              ),
              const SizedBox(height: 12),
              _buildBulletPoint(
                context,
                'Flexible payments',
                'Pay with card or crypto (ETH, SOL, USDC, ARIO)',
              ),
              const SizedBox(height: 8),
              _buildBulletPoint(
                context,
                'Instant uploads',
                'No waiting for blockchain confirmations',
              ),
              const SizedBox(height: 8),
              _buildBulletPoint(
                context,
                'Same value as AR',
                'Turbo Credits have identical storage purchasing power',
              ),
              const SizedBox(height: 20),

              // Upload limits section
              Text(
                'Upload Limits by Browser',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                  color: colorTokens.textHigh,
                ),
              ),
              const SizedBox(height: 12),
              _buildTable(
                context,
                headers: ['Browser', 'Max file size'],
                rows: [
                  ['Chrome/Edge/Brave', '10 GiB'],
                  ['Safari', '500 MiB'],
                  ['Firefox', '500 MiB'],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'For larger files, use Chrome, Edge, or Brave browsers.',
                style: typography.paragraphSmall(
                  color: colorTokens.textLow,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Helper widget for bullet points
Widget _buildBulletPoint(
    BuildContext context, String title, String description) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: colorTokens.textMid,
            shape: BoxShape.circle,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$title: ',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textHigh,
                ),
              ),
              TextSpan(
                text: description,
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// Helper widget for tables
Widget _buildTable(
  BuildContext context, {
  required List<String> headers,
  required List<List<String>> rows,
}) {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return Container(
    decoration: BoxDecoration(
      border: Border.all(color: colorTokens.strokeLow),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorTokens.containerL2,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Row(
            children: headers.map((header) {
              return Expanded(
                child: Text(
                  header,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.bold,
                    color: colorTokens.textHigh,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }).toList(),
          ),
        ),
        // Data rows
        ...rows.asMap().entries.map((entry) {
          final isLast = entry.key == rows.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(color: colorTokens.strokeLow),
                    ),
            ),
            child: Row(
              children: entry.value.map((cell) {
                return Expanded(
                  child: Text(
                    cell,
                    style: typography.paragraphNormal(
                      color: colorTokens.textMid,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }).toList(),
            ),
          );
        }),
      ],
    ),
  );
}

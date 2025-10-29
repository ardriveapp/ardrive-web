import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Shows a modal with licensing information
Future<void> showLicensingInfoModal({
  required BuildContext context,
}) async {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      hasCloseButton: true,
      title: 'Licensing Your Data',
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apply licenses to control how others can use your content.',
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Available Options',
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: 12),
            _buildBulletPoint(
              context,
              'Universal Data License (UDL)',
              'For blockchain-based storage',
            ),
            const SizedBox(height: 8),
            _buildBulletPoint(
              context,
              'Creative Commons',
              'Six license types from permissive to restrictive',
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorTokens.containerL2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: ArDriveIcons.info(
                      size: 16,
                      color: colorTokens.textMid,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Licenses are free to apply and visible in file details. Select a file after upload to add a license.',
                      style: typography.paragraphSmall(
                        color: colorTokens.textMid,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows a modal explaining keyfile and seed phrase login
Future<void> showKeyfileInfoModal({
  required BuildContext context,
}) async {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      hasCloseButton: true,
      title: 'Keyfile & Seed Phrase',
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keyfiles',
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Arweave wallet file that authenticates your identity. You will need your keyfile and password to log in.',
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Seed Phrases',
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A sequence of words that can generate your wallet. Enter your seed phrase and password to access your account.',
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorTokens.containerRed,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: ArDriveIcons.triangle(
                      size: 16,
                      color: colorTokens.textHigh,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Keep your keyfile and seed phrase secure. Anyone with access can control your account. ArDrive cannot recover lost credentials.',
                      style: typography.paragraphSmall(
                        color: colorTokens.textHigh,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows a modal with ArDrive app limits
Future<void> showAppLimitsInfoModal({
  required BuildContext context,
}) async {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      hasCloseButton: true,
      title: 'Upload & Download Limits',
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upload Size Limits',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                  color: colorTokens.textHigh,
                ),
              ),
              const SizedBox(height: 12),
              _buildTable(
                context,
                headers: ['Browser', 'Direct (AR)', 'Turbo'],
                rows: [
                  ['Chrome/Edge/Brave', '65 GiB', '10 GiB'],
                  ['Safari', '65 GiB', '500 MiB'],
                  ['Firefox', '65 GiB', '500 MiB'],
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'File Count: Chrome/Brave (1,500 files), Firefox (10,000 files)',
                style: typography.paragraphSmall(
                  color: colorTokens.textLow,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Download Size Limits',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                  color: colorTokens.textHigh,
                ),
              ),
              const SizedBox(height: 12),
              _buildTable(
                context,
                headers: ['Browser', 'Max Size'],
                rows: [
                  ['Chrome/Edge/Brave', '15 GiB'],
                  ['Safari', '1 GiB'],
                  ['Firefox', '15 GiB'],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Helper widget for bullet points
Widget _buildBulletPoint(BuildContext context, String title, String description) {
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

// PROTOTYPE - for design review on the preview build, not for release.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/permanence/spend_estimate.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;

/// Turbo's current prices, from its public `GET /v1/rates`.
class TurboRates {
  const TurboRates({required this.usdPerGb, required this.usdPerUnit});

  /// What 1 GB of storage costs, in US dollars.
  final double usdPerGb;

  /// What one whole unit of each currency is worth in US dollars, by
  /// lower-case code. Worked out from the price of a GB in each currency.
  final Map<String, double> usdPerUnit;
}

Future<TurboRates?> fetchTurboRates(String paymentUrl) async {
  try {
    final response = await http
        .get(Uri.parse('$paymentUrl/v1/rates'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final fiat = (body['fiat'] as Map<String, dynamic>)
        .map((code, perGb) => MapEntry(code, (perGb as num).toDouble()));
    final usdPerGb = fiat['usd'];

    if (usdPerGb == null) {
      return null;
    }

    return TurboRates(
      usdPerGb: usdPerGb,
      usdPerUnit: {
        for (final entry in fiat.entries)
          if (entry.value > 0) entry.key: usdPerGb / entry.value,
      },
    );
  } catch (_) {
    return null;
  }
}

/// How reading the wallet's spending went.
class SpendLookup {
  const SpendLookup._({this.estimate, this.failed = false});

  /// The history could not be read: a signature the wallet refused, the
  /// service unreachable. Not the same as there being nothing to read.
  const SpendLookup.failed() : this._(failed: true);

  /// The history was read, and holds no top-ups.
  const SpendLookup.none() : this._();

  const SpendLookup.found(SpendEstimate estimate) : this._(estimate: estimate);

  final SpendEstimate? estimate;
  final bool failed;
}

/// What [wallet] has spent on storage, from its Turbo top-ups. See
/// [estimateSpend].
Future<SpendLookup> loadSpendEstimate({
  required PaymentService paymentService,
  required Wallet wallet,
  required TurboRates rates,
}) async {
  final List<Map<String, dynamic>> history;

  try {
    history = await paymentService.getPaymentHistory(wallet: wallet);
  } catch (e) {
    logger.w('Could not read the Turbo payment history: $e');
    return const SpendLookup.failed();
  }

  // PROTOTYPE: what the rows look like, to check the reading of them against
  // real accounts. Kinds and amounts only - no ids, no addresses.
  final rows = history
      .map((row) => row['type'] == 'crypto'
          ? 'crypto ${row['tokenType']} usd=${row['usdEquivalent']}'
          : 'fiat ${row['paymentProvider']} ${row['currencyType']} '
              'amount=${row['paymentAmount']} '
              'gift=${row['giftMessage'] != null}')
      .join('; ');
  logger.i('Turbo payment history: ${history.length} rows - $rows');

  BigInt balance;
  try {
    balance = await paymentService.getBalance(wallet: wallet);
  } on TurboUserNotFound {
    balance = BigInt.zero;
  } catch (e) {
    logger.w('Could not read the Turbo balance: $e');
    return const SpendLookup.failed();
  }

  final estimate = estimateSpend(
    topUps: [
      for (final row in history)
        TurboTopUp.fromJson(row, usdPerUnit: rates.usdPerUnit),
    ],
    balanceWinc: balance,
  );

  return estimate == null
      ? const SpendLookup.none()
      : SpendLookup.found(estimate);
}

/// What the permanence panel shows.
class PermanenceSummary {
  const PermanenceSummary({
    required this.totalBytes,
    required this.fileCount,
    required this.driveCount,
    required this.bytesByYear,
    required this.usdPerGb,
    this.spend,
  });

  final int totalBytes;
  final int fileCount;
  final int driveCount;

  /// Bytes uploaded in each year, oldest first.
  final Map<int, int> bytesByYear;

  /// Turbo's current price for 1 GB, in US dollars.
  final double? usdPerGb;

  /// What the wallet has spent, still arriving when the panel opens.
  final Future<SpendLookup>? spend;

  static const _gb = 1024 * 1024 * 1024;

  double get gb => totalBytes / _gb;

  double? get costToday => usdPerGb == null ? null : gb * usdPerGb!;

  int? get firstYear => bytesByYear.isEmpty ? null : bytesByYear.keys.first;
}

final _usd = NumberFormat.currency(symbol: r'$', decimalDigits: 0);
final _usdCents = NumberFormat.currency(symbol: r'$', decimalDigits: 2);

String _formatGb(double gb) =>
    gb >= 10 ? '${gb.toStringAsFixed(0)} GB' : '${gb.toStringAsFixed(1)} GB';

void showPermanencePanel(BuildContext context, PermanenceSummary summary) {
  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      width: 460,
      hasCloseButton: true,
      titleWidget: Text(
        'Your permanence',
        style: ArDriveTypographyNew.of(context).heading3(
          fontWeight: ArFontWeight.bold,
        ),
      ),
      content: PermanencePanel(summary: summary),
    ),
  );
}

class PermanencePanel extends StatelessWidget {
  const PermanencePanel({super.key, required this.summary});

  final PermanenceSummary summary;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final costToday = summary.costToday;

    Widget tile(String label, String value, String note) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.containerL2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: typography.caption(
                      color: colors.textLow,
                      fontWeight: ArFontWeight.semiBold,
                    )),
                const SizedBox(height: 6),
                Text(value,
                    style: typography.heading3(
                      color: colors.textHigh,
                      fontWeight: ArFontWeight.bold,
                    )),
                const SizedBox(height: 2),
                Text(note,
                    style: typography.caption(
                      color: colors.textLow,
                      fontWeight: ArFontWeight.book,
                    )),
              ],
            ),
          ),
        );

    final spentTile = FutureBuilder<SpendLookup>(
      future: summary.spend,
      builder: (context, snapshot) {
        if (summary.spend == null) {
          return tile('SPENT', '-', "couldn't read your top-ups");
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return tile('SPENT', '...', 'reading your top-ups');
        }

        final lookup = snapshot.data;
        final spend = lookup?.estimate;

        if (lookup == null || lookup.failed) {
          return tile('SPENT', '-', "couldn't read your top-ups");
        }

        if (spend == null) {
          return tile('SPENT', '-', 'no top-ups found');
        }

        String plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

        if (spend.paidCount == 0) {
          return tile(
            'SPENT',
            _usd.format(0),
            '${plural(spend.grantCount, 'credit grant')}, nothing bought',
          );
        }

        return tile(
          'SPENT',
          _usd.format(spend.usd),
          'estimated, from ${plural(spend.paidCount, 'top-up')}',
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Text(
          '${_formatGb(summary.gb)} preserved',
          style: typography.heading1(
            color: colors.textHigh,
            fontWeight: ArFontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            '${NumberFormat.decimalPattern().format(summary.fileCount)} files',
            '${summary.driveCount} drives',
            if (summary.firstYear != null) 'since ${summary.firstYear}',
          ].join(' · '),
          style: typography.paragraphNormal(
            color: colors.textMid,
            fontWeight: ArFontWeight.book,
          ),
        ),
        if (summary.bytesByYear.isNotEmpty) ...[
          const SizedBox(height: 20),
          SizedBox(
            height: 130,
            child: CustomPaint(
              painter: _StrataPainter(
                bytesByYear: summary.bytesByYear,
                brand: colors.buttonPrimaryDefault,
                base: colors.containerL1,
                label: colors.textHigh,
                muted: colors.textLow,
                labelStyle: typography.caption(fontWeight: ArFontWeight.bold),
                mutedStyle: typography.caption(fontWeight: ArFontWeight.book),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Each layer is a year of uploads. The oldest are at the bottom.',
            style: typography.caption(
              color: colors.textLow,
              fontWeight: ArFontWeight.book,
            ),
          ),
        ],
        const SizedBox(height: 20),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              spentTile,
              const SizedBox(width: 12),
              tile(
                'COST TODAY',
                costToday == null ? '-' : _usd.format(costToday),
                'to store it all now',
              ),
            ],
          ),
        ),
        if (costToday != null) ...[
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              style: typography.paragraphNormal(
                color: colors.textMid,
                fontWeight: ArFontWeight.book,
              ),
              children: [
                const TextSpan(text: 'Paid once. Stored for ~200 years. '),
                TextSpan(
                  text: "That's ${_usdCents.format(costToday / 200)} a year.",
                  style: typography.paragraphNormal(
                    color: colors.textHigh,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Across your synced drives. Files you own, counted once.',
          style: typography.caption(
            color: colors.textLow,
            fontWeight: ArFontWeight.book,
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: ArDriveButtonNew(
            text: 'Share my permanence',
            typography: typography,
            variant: ButtonVariant.outline,
            maxWidth: 220,
            onPressed: () => showPermanenceShare(context, summary),
          ),
        ),
      ],
    );
  }
}

/// The text that goes with the share card. No dollar amounts: what someone
/// spent is theirs to tell.
String permanenceShareText(PermanenceSummary summary) => [
      '${_formatGb(summary.gb)} of my files, stored on Arweave for ~200 years',
      if (summary.firstYear != null) 'Preserving since ${summary.firstYear}.',
      'ardrive.io',
    ].join('. ').replaceAll('..', '.');

void showPermanenceShare(BuildContext context, PermanenceSummary summary) {
  final cardKey = GlobalKey();
  final typography = ArDriveTypographyNew.of(context);

  showArDriveDialog(
    context,
    content: StatefulBuilder(
      builder: (context, setState) => ArDriveStandardModalNew(
        width: 560,
        hasCloseButton: true,
        titleWidget: Text(
          'Share your permanence',
          style: typography.heading3(fontWeight: ArFontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            // Drawn at 600 x 315 and saved at twice that: the 1200 x 630
            // that social sites expect for a link card.
            FittedBox(
              child: RepaintBoundary(
                key: cardKey,
                child: PermanenceShareCard(summary: summary),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              permanenceShareText(summary),
              style: typography.paragraphSmall(
                color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
                fontWeight: ArFontWeight.book,
              ),
            ),
          ],
        ),
        actions: [
          ModalAction(
            title: 'Copy text',
            action: () {
              Clipboard.setData(
                ClipboardData(text: permanenceShareText(summary)),
              );
              Navigator.of(context).pop();
            },
          ),
          ModalAction(
            title: 'Download image',
            action: () async {
              final boundary = cardKey.currentContext?.findRenderObject()
                  as RenderRepaintBoundary?;

              if (boundary == null) {
                return;
              }

              final image = await boundary.toImage(pixelRatio: 2);
              final png =
                  await image.toByteData(format: ui.ImageByteFormat.png);

              if (png == null) {
                return;
              }

              await ArDriveIO().saveFile(
                await IOFile.fromData(
                  png.buffer.asUint8List(),
                  name: 'my-permanence.png',
                  lastModifiedDate: DateTime.now(),
                  contentType: 'image/png',
                ),
              );

              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// The card people share: the size, the years and the strata, on the brand's
/// dark ground. Always dark, whatever the app's theme, so it looks the same
/// wherever it is posted.
class PermanenceShareCard extends StatelessWidget {
  const PermanenceShareCard({super.key, required this.summary});

  final PermanenceSummary summary;

  static const _ground = Color(0xFF0E0E0F);
  static const _brand = Color(0xFFFE0230);
  static const _text = Color(0xFFFAFAFA);
  static const _muted = Color(0xFFA3A3A3);

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      width: 600,
      height: 315,
      color: _ground,
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  Resources.images.brand.whiteLogo2,
                  height: 22,
                ),
                const Spacer(),
                Text(
                  _formatGb(summary.gb),
                  style: typography
                      .display(fontWeight: ArFontWeight.bold)
                      .copyWith(color: _text, height: 1),
                ),
                const SizedBox(height: 6),
                Text(
                  'preserved for ~200 years',
                  style: typography.paragraphLarge(
                    color: _text,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (summary.firstYear != null) 'Since ${summary.firstYear}',
                    '${NumberFormat.decimalPattern().format(summary.fileCount)} files',
                  ].join(' · '),
                  style: typography.paragraphNormal(
                    color: _muted,
                    fontWeight: ArFontWeight.book,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 4,
            child: CustomPaint(
              painter: _StrataPainter(
                bytesByYear: summary.bytesByYear,
                brand: _brand,
                base: _ground,
                label: _text,
                muted: _muted,
                labelStyle: typography.caption(fontWeight: ArFontWeight.bold),
                mutedStyle: typography.caption(fontWeight: ArFontWeight.book),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The archive as rock strata: one band per year of uploads, oldest at the
/// bottom, thickness by size.
class _StrataPainter extends CustomPainter {
  _StrataPainter({
    required this.bytesByYear,
    required this.brand,
    required this.base,
    required this.label,
    required this.muted,
    required this.labelStyle,
    required this.mutedStyle,
  });

  final Map<int, int> bytesByYear;
  final Color brand;
  final Color base;
  final Color label;
  final Color muted;
  final TextStyle labelStyle;
  final TextStyle mutedStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (bytesByYear.isEmpty) {
      return;
    }

    const labelWidth = 104.0;
    const minBand = 16.0;
    final layers = bytesByYear.entries.toList();
    final bandWidth = size.width - labelWidth;
    final total = layers.fold<int>(0, (a, e) => a + e.value);
    final flex = math.max(0.0, size.height - minBand * layers.length);

    final tops = <double>[];
    var bottom = size.height;
    for (final layer in layers) {
      bottom -= minBand + flex * (total == 0 ? 0 : layer.value / total);
      tops.add(bottom);
    }

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, bandWidth, size.height),
      const Radius.circular(8),
    ));

    // The newest first, so each older layer is drawn over it.
    for (var i = layers.length - 1; i >= 0; i--) {
      final t = (i + 1) / layers.length;
      final color = Color.lerp(base, brand, 0.2 + 0.8 * t * t)!;
      final amp = i == layers.length - 1 ? 0.0 : 3.0;
      final path = Path()
        ..moveTo(0, size.height)
        ..lineTo(0, tops[i]);
      for (var x = 0.0; x <= bandWidth; x += 4) {
        path.lineTo(
          x,
          tops[i] + amp * math.sin((x / bandWidth) * 5 * math.pi + i * 1.7),
        );
      }
      path
        ..lineTo(bandWidth, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }
    canvas.restore();

    var below = size.height;
    for (var i = 0; i < layers.length; i++) {
      final mid = (tops[i] + below) / 2;
      final year = TextPainter(
        text: TextSpan(
          text: '${layers[i].key}',
          style: labelStyle.copyWith(color: label),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final gb = TextPainter(
        text: TextSpan(
          text: _formatGb(layers[i].value / PermanenceSummary._gb),
          style: mutedStyle.copyWith(color: muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      year.paint(canvas, Offset(bandWidth + 12, mid - year.height / 2));
      gb.paint(canvas, Offset(bandWidth + 52, mid - gb.height / 2));
      below = tops[i];
    }
  }

  @override
  bool shouldRepaint(covariant _StrataPainter old) =>
      old.bytesByYear != bytesByYear || old.brand != brand;
}

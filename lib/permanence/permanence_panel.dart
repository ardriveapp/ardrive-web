// PROTOTYPE - for design review on a local branch, not for merge.
import 'dart:convert';
import 'dart:math' as math;

import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;

/// What the permanence panel shows.
class PermanenceSummary {
  const PermanenceSummary({
    required this.totalBytes,
    required this.fileCount,
    required this.driveCount,
    required this.bytesByYear,
    required this.usdPerGb,
  });

  final int totalBytes;
  final int fileCount;
  final int driveCount;

  /// Bytes uploaded in each year, oldest first.
  final Map<int, int> bytesByYear;

  /// Turbo's current price for 1 GB, in US dollars. Null when it could not be
  /// fetched.
  final double? usdPerGb;

  static const _gb = 1024 * 1024 * 1024;

  double get gb => totalBytes / _gb;

  double? get costToday => usdPerGb == null ? null : gb * usdPerGb!;

  int? get firstYear => bytesByYear.isEmpty ? null : bytesByYear.keys.first;
}

/// Turbo's price for 1 GB of storage, in US dollars.
Future<double?> fetchUsdPerGb(String paymentUrl) async {
  try {
    final response = await http
        .get(Uri.parse('$paymentUrl/v1/rates'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['fiat'] as Map<String, dynamic>)['usd'] as double?;
  } catch (_) {
    return null;
  }
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
    // Prototype only: the history endpoint needs a signed request, so this is
    // a sample figure until that is wired.
    final spentSample = costToday == null ? null : costToday * 1.12;

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
              tile(
                'SPENT',
                spentSample == null ? '-' : _usd.format(spentSample),
                'sample until history is wired',
              ),
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
            text: 'Share my archive',
            typography: typography,
            variant: ButtonVariant.outline,
            maxWidth: 180,
            onPressed: () {},
          ),
        ),
      ],
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

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/permanence/spend_estimate.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

  double? get costToday =>
      usdPerGb == null ? null : totalBytes / _gb * usdPerGb!;

  int? get firstYear => bytesByYear.isEmpty ? null : bytesByYear.keys.first;
}

final _usd = NumberFormat.currency(symbol: r'$', decimalDigits: 0);
final _usdCents = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
final _count = NumberFormat.decimalPattern();

/// A dollar figure as the permanence panel shows it: whole dollars, with
/// thousands separated.
String formatPermanenceUsd(double usd) => _usd.format(usd);

/// Sizes in the units people think in, to one decimal place until that
/// stops meaning anything.
String _formatSize(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  const tb = gb * 1024;

  String scaled(double value, String unit) => value >= 100
      ? '${_count.format(value.round())} $unit'
      : '${value.toStringAsFixed(1)} $unit';

  if (bytes >= tb) return scaled(bytes / tb, 'TB');
  if (bytes >= gb) return scaled(bytes / gb, 'GB');
  if (bytes >= mb) return scaled(bytes / mb, 'MB');
  return scaled(bytes / kb, 'KB');
}

/// Between items in a line of facts. Wavehaus draws its middle dot low and
/// small, so it read as a full stop; its bullet sits on the line's middle.
const _separator = '  •  ';

String _plural(int n, String one) =>
    '${_count.format(n)} $one${n == 1 ? '' : 's'}';

void showPermanencePanel(BuildContext context, PermanenceSummary summary) {
  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      width: 460,
      hasCloseButton: true,
      scrollableContent: true,
      titleWidget: Text(
        'Your permanence',
        style: ArDriveTypographyNew.of(context).heading3(
          fontWeight: ArFontWeight.bold,
        ),
      ),
      content: PermanencePanel(summary: summary),
      actions: [
        ModalAction(
          title: 'Share my permanence',
          customWidth: 240,
          action: () {
            Navigator.of(context).pop();
            showPermanenceShare(context, summary);
          },
        ),
      ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: _formatSize(summary.totalBytes),
                style: typography.heading1(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.bold,
                ),
              ),
              TextSpan(
                text: '  preserved',
                style: typography.paragraphXLarge(
                  color: colors.textMid,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            _plural(summary.fileCount, 'file'),
            _plural(summary.driveCount, 'drive'),
            if (summary.firstYear != null) 'since ${summary.firstYear}',
          ].join(_separator),
          style: typography.paragraphNormal(
            color: colors.textLow,
            fontWeight: ArFontWeight.book,
          ),
        ),
        if (summary.bytesByYear.isNotEmpty) ...[
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: _StrataPainter(
                bytesByYear: summary.bytesByYear,
                brand: colors.buttonPrimaryDefault,
                faint: colors.textOnPrimary,
                outline: colors.strokeLow,
                label: colors.textHigh,
                muted: colors.textLow,
                labelStyle: typography.caption(fontWeight: ArFontWeight.bold),
                mutedStyle: typography.caption(fontWeight: ArFontWeight.book),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, box) {
          final spendTile = _SpendTile(spend: summary.spend);
          final costTile = _Tile(
            label: 'COST TODAY',
            value: costToday == null ? '-' : _usd.format(costToday),
            note: "at Turbo's current price",
          );

          // Side by side they are under 120px wide on a phone, and their
          // notes broke mid-word. Stacked, each keeps its line.
          if (box.maxWidth < 380) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [spendTile, const SizedBox(height: 12), costTile],
            );
          }

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: spendTile),
                const SizedBox(width: 12),
                Expanded(child: costTile),
              ],
            ),
          );
        }),
        if (costToday != null) ...[
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              style: typography.paragraphNormal(
                color: colors.textMid,
                fontWeight: ArFontWeight.book,
              ),
              children: [
                const TextSpan(text: 'Designed to be permanent: about '),
                TextSpan(
                  text: '${_usdCents.format(costToday / 200)} a year',
                  style: typography.paragraphNormal(
                    color: colors.textHigh,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
                const TextSpan(text: ' over 200 years, at today\'s price.'),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const _FinePrint(),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.note});

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        // A step off the modal's own ground (containerL3), in either theme.
        color: colors.containerL1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: typography
                .caption(
                  color: colors.textLow,
                  fontWeight: ArFontWeight.semiBold,
                )
                .copyWith(letterSpacing: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: typography.heading3(
              color: colors.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: typography.caption(
              color: colors.textLow,
              fontWeight: ArFontWeight.book,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the wallet has spent, as it arrives.
class _SpendTile extends StatelessWidget {
  const _SpendTile({required this.spend});

  final Future<SpendLookup>? spend;

  static const _label = 'ESTIMATED SPEND';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpendLookup>(
      future: spend,
      builder: (context, snapshot) {
        if (spend == null) {
          return const _Tile(
              label: _label, value: '-', note: "couldn't read your top-ups");
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const _Tile(
              label: _label, value: '...', note: 'reading your top-ups');
        }

        final lookup = snapshot.data;
        final estimate = lookup?.estimate;

        if (lookup == null || lookup.failed) {
          return const _Tile(
              label: _label, value: '-', note: "couldn't read your top-ups");
        }

        if (estimate == null) {
          return const _Tile(
              label: _label, value: '-', note: 'no top-ups found');
        }

        if (estimate.paidCount == 0) {
          return _Tile(
            label: _label,
            value: _usd.format(0),
            note: '${_plural(estimate.grantCount, 'credit grant')}, '
                'nothing bought',
          );
        }

        return _Tile(
          label: _label,
          value: _usd.format(estimate.usd),
          note: 'from ${_plural(estimate.paidCount, 'top-up')}',
        );
      },
    );
  }
}

/// How the panel's numbers are made, one tap away. Closed by default, so the
/// panel stays a summary; open, it says plainly what each figure is and is
/// not.
class _FinePrint extends StatefulWidget {
  const _FinePrint();

  @override
  State<_FinePrint> createState() => _FinePrintState();
}

class _FinePrintState extends State<_FinePrint> {
  bool _open = false;

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final body = typography.caption(
      color: colors.textMid,
      fontWeight: ArFontWeight.book,
    );

    Widget point(InlineSpan text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 10),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textLow,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(child: Text.rich(text, style: body)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArDriveClickArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Semantics(
              button: true,
              expanded: _open,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'How these numbers work',
                    style: typography.caption(
                      color: colors.textMid,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: _duration,
                    child: ArDriveIcons.carretDown(
                      size: 14,
                      color: colors.textMid,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: _duration,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      point(const TextSpan(
                        text: 'Sizes count the drives synced on this device: '
                            'data you uploaded, each piece once, once its '
                            'upload is confirmed. Pinned files are not '
                            'included.',
                      )),
                      point(const TextSpan(
                        text: 'Estimated spend comes from your Turbo '
                            "top-ups. It isn't a receipt, and doesn't "
                            'include uploads paid for directly in AR.',
                      )),
                      point(const TextSpan(
                        text: "Cost today uses Turbo's current price, which "
                            'changes. It is not a quote.',
                      )),
                      point(TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Permanence is provided by the Arweave '
                                'network, whose storage endowment is '
                                'designed to fund data for 200+ years. See '
                                'the ',
                          ),
                          TextSpan(
                            text: 'Terms of Service',
                            style: body.copyWith(
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap =
                                  () => openUrl(url: Resources.agreementLink),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      )),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// The text that goes with the share card. No dollar amounts: what someone
/// spent is theirs to tell. No promise of a duration, either.
String permanenceShareText(PermanenceSummary summary) => [
      '${_formatSize(summary.totalBytes)} of my files, stored to be '
          'permanent on Arweave.',
      if (summary.firstYear != null) 'Preserving since ${summary.firstYear}.',
      'ardrive.io',
    ].join(' ');

void showPermanenceShare(BuildContext context, PermanenceSummary summary) {
  final cardKey = GlobalKey();
  final typography = ArDriveTypographyNew.of(context);

  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      width: 600,
      hasCloseButton: true,
      scrollableContent: true,
      titleWidget: Text(
        'Share your permanence',
        style: typography.heading3(fontWeight: ArFontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          // Drawn at 600 x 315 and saved at twice that: the 1200 x 630 that
          // social sites expect for a link card.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FittedBox(
              child: RepaintBoundary(
                key: cardKey,
                child: PermanenceShareCard(summary: summary),
              ),
            ),
          ),
          const SizedBox(height: 16),
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
          customWidth: 120,
          action: () {
            Clipboard.setData(
              ClipboardData(text: permanenceShareText(summary)),
            );
            Navigator.of(context).pop();
          },
        ),
        ModalAction(
          title: 'Download image',
          customWidth: 160,
          action: () async {
            final boundary = cardKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;

            if (boundary == null) {
              return;
            }

            final image = await boundary.toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);

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
  static const _white = Color(0xFFFFFFFF);
  static const _muted = Color(0xFF9A9A9A);

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      width: 600,
      height: 315,
      color: _ground,
      padding: const EdgeInsets.fromLTRB(36, 32, 32, 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(Resources.images.brand.whiteLogo2, height: 24),
                const Spacer(),
                Text(
                  _formatSize(summary.totalBytes),
                  style: typography
                      .display(fontWeight: ArFontWeight.bold)
                      .copyWith(color: _text, fontSize: 56, height: 1),
                ),
                const SizedBox(height: 10),
                Text(
                  'stored to be permanent',
                  style: typography.paragraphXLarge(
                    color: _text,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (summary.firstYear != null) 'Since ${summary.firstYear}',
                    _plural(summary.fileCount, 'file'),
                  ].join(_separator),
                  style: typography.paragraphNormal(
                    color: _muted,
                    fontWeight: ArFontWeight.book,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            flex: 9,
            child: CustomPaint(
              painter: _StrataPainter(
                bytesByYear: summary.bytesByYear,
                brand: _brand,
                faint: _white,
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
    required this.faint,
    this.outline,
    required this.label,
    required this.muted,
    required this.labelStyle,
    required this.mutedStyle,
  });

  final Map<int, int> bytesByYear;
  final Color brand;

  /// The quietest year's colour: the palette's white.
  final Color faint;

  /// Drawn round the bands, so a white one still has an edge on a light
  /// ground.
  final Color? outline;
  final Color label;
  final Color muted;
  final TextStyle labelStyle;
  final TextStyle mutedStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (bytesByYear.isEmpty) {
      return;
    }

    const labelWidth = 112.0;
    const minBand = 16.0;
    final layers = bytesByYear.entries.toList();
    final bandWidth = size.width - labelWidth;
    final total = layers.fold<int>(0, (a, e) => a + e.value);
    final maxBytes = layers.fold<int>(0, (a, e) => math.max(a, e.value));
    final minBytes = layers.fold<int>(maxBytes, (a, e) => math.min(a, e.value));
    final flex = math.max(0.0, size.height - minBand * layers.length);

    final tops = <double>[];
    var bottom = size.height;
    for (final layer in layers) {
      bottom -= minBand + flex * (total == 0 ? 0 : layer.value / total);
      tops.add(bottom);
    }

    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, bandWidth, size.height),
      const Radius.circular(8),
    );

    canvas.save();
    canvas.clipRRect(frame);

    // The newest first, so each older layer is drawn over it.
    for (var i = layers.length - 1; i >= 0; i--) {
      // A heat map, the full width of the palette: the quietest year is
      // white, the busiest the brand red. Position already says how old a
      // layer is, so colour says how much.
      final range = maxBytes - minBytes;
      final heat = range == 0 ? 1.0 : (layers[i].value - minBytes) / range;
      final color = Color.lerp(faint, brand, heat)!;
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

    final outline = this.outline;
    if (outline != null) {
      canvas.drawRRect(
        frame.deflate(0.5),
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

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
      final amount = TextPainter(
        text: TextSpan(
          text: _formatSize(layers[i].value),
          style: mutedStyle.copyWith(color: muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      year.paint(canvas, Offset(bandWidth + 14, mid - year.height / 2));
      amount.paint(canvas, Offset(bandWidth + 54, mid - amount.height / 2));
      below = tops[i];
    }
  }

  @override
  bool shouldRepaint(covariant _StrataPainter old) =>
      old.bytesByYear != bytesByYear ||
      old.brand != brand ||
      old.faint != faint;
}

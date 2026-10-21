import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/permanence/ar_spend.dart';
import 'package:ardrive/permanence/permanence_cache.dart';
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

/// What the Arweave network charges, today, to store a given size for good.
class NetworkCost {
  const NetworkCost({required this.winston, required this.usdPerAr});

  /// The network's price, from a gateway's `/price` for the exact size.
  final BigInt winston;

  /// What one AR is worth in US dollars now. Null when it could not be read,
  /// and the price is shown in AR alone.
  final double? usdPerAr;

  double get ar => winston / BigInt.from(10).pow(12);

  double? get usd => usdPerAr == null ? null : ar * usdPerAr!;
}

/// What one AR is worth in US dollars now, from Turbo's public
/// `GET /v1/rates/usd`.
Future<double?> fetchUsdPerAr(String paymentUrl) async {
  try {
    final response = await http
        .get(Uri.parse('$paymentUrl/v1/rates/usd'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      return null;
    }

    final rate = (jsonDecode(response.body) as Map<String, dynamic>)['rate'];
    return rate is num && rate > 0 ? rate.toDouble() : null;
  } catch (_) {
    return null;
  }
}

/// The network's price for the size, and the dollar rate beside it. Null when
/// the price itself could not be read.
Future<NetworkCost?> loadNetworkCost({
  required Future<BigInt> Function() price,
  required Future<double?> usdPerAr,
}) async {
  final BigInt winston;

  try {
    winston = await price();
  } catch (e) {
    logger.w('Could not read the network price for the permanence panel: $e');
    return null;
  }

  return NetworkCost(winston: winston, usdPerAr: await usdPerAr);
}

/// How reading the wallet's Turbo credits went.
class SpendLookup {
  const SpendLookup._({
    this.creditsWinc,
    this.failed = false,
    this.tooMany = false,
  });

  /// The history could not be read: a signature the wallet refused, the
  /// service unreachable. Not the same as there being nothing to read.
  const SpendLookup.failed() : this._(failed: true);

  /// The history was read, and holds no top-ups.
  const SpendLookup.none() : this._();

  /// More top-ups than one look reads. Credits used from some of them, set
  /// against the whole balance, would be wrong and look right, so there is
  /// no figure.
  const SpendLookup.tooMany() : this._(tooMany: true);

  const SpendLookup.found(BigInt creditsWinc)
      : this._(creditsWinc: creditsWinc);

  /// Turbo credits used, in winc. See [creditsUsed].
  final BigInt? creditsWinc;
  final bool failed;
  final bool tooMany;
}

/// The Turbo credits [wallet] has used. See [creditsUsed].
Future<SpendLookup> loadCreditsSpent({
  required PaymentService paymentService,
  required Wallet wallet,
}) async {
  final List<Map<String, dynamic>> history;

  try {
    final read = await paymentService.getPaymentHistory(wallet: wallet);

    if (!read.complete) {
      return const SpendLookup.tooMany();
    }

    history = read.payments;
  } catch (e) {
    logger.w('Could not read the Turbo payment history: $e');
    return const SpendLookup.failed();
  }

  if (history.isEmpty) {
    return const SpendLookup.none();
  }

  // The wallet's own credits: what it can spend would count credits shared
  // with it, which came with no top-up. See [creditsUsed].
  BigInt balance;
  try {
    balance = (await paymentService.getBalanceAndPaidBy(wallet: wallet))
        .controlledWinc;
  } on TurboUserNotFound {
    balance = BigInt.zero;
  } catch (e) {
    logger.w('Could not read the Turbo balance: $e');
    return const SpendLookup.failed();
  }

  return SpendLookup.found(
    creditsUsed(payments: history, balanceWinc: balance),
  );
}

/// What the permanence panel shows.
class PermanenceSummary {
  const PermanenceSummary({
    required this.totalBytes,
    required this.fileCount,
    required this.driveCount,
    required this.bytesByYear,
    this.costToday,
    this.spend,
    this.loadSpend,
    this.cachedSpend,
    this.arSpend,
    this.signInChain,
  });

  final int totalBytes;
  final int fileCount;
  final int driveCount;

  /// Bytes uploaded in each year, oldest first.
  final Map<int, int> bytesByYear;

  /// What the network charges today to store [totalBytes], as it arrives.
  final Future<NetworkCost?>? costToday;

  /// What the wallet has spent, still arriving when the panel opens.
  final Future<SpendLookup>? spend;

  /// Reads what the wallet has spent when the reader asks, in place of
  /// [spend], for a wallet that would ask its owner to sign: a browser
  /// extension shows a prompt for every signature, and one that opens with
  /// a summary nobody asked to sign for reads as something gone wrong.
  final Future<SpendLookup> Function()? loadSpend;

  /// An earlier reading of what the wallet has spent, shown with the time it
  /// was read until [spend] arrives, or beside the way to read it again.
  final SpendEntry? cachedSpend;

  /// What the wallet paid in AR to upload directly, counted as it arrives.
  /// Null when it could not be asked.
  final Future<ArSpendTally>? arSpend;

  /// The chain of the wallet the reader signed in with ("Ethereum",
  /// "Solana"), when it was not an Arweave one. Credits that wallet shared
  /// with the Arweave wallet made for it are spent here, but are in neither
  /// one's own history as this reads it, so the fine print says so: to
  /// them, and to nobody else.
  final String? signInChain;

  int? get firstYear => bytesByYear.isEmpty ? null : bytesByYear.keys.first;
}

/// Dollars as the cost today is shown: whole dollars from $100 up, cents
/// below that, and "<$0.01" for less than a cent.
///
/// It was whole dollars throughout, so a few MiB, which costs cents to store,
/// read as "$0" beside a real AR price.
@visibleForTesting
String formatUsd(double usd) {
  // From the first amount that rounds to $100.00 in cents, so nothing reads
  // "$100.00" beside "$100".
  if (usd >= 99.995) {
    return NumberFormat.currency(symbol: r'$', decimalDigits: 0).format(usd);
  }
  if (usd > 0 && usd < 0.01) {
    return r'<$0.01';
  }
  return NumberFormat.currency(symbol: r'$', decimalDigits: 2).format(usd);
}

final _count = NumberFormat.decimalPattern();

/// Sizes to one decimal place until that stops meaning anything. The profile
/// card uses it too, so its line and the panel always say the same size the
/// same way.
///
/// In the units the rest of the app counts in (KiB, MiB, GiB, as `filesize`
/// prints them), so the drives list and this line measure alike.
String formatPermanenceSize(int bytes) => _formatSize(bytes);

String _formatSize(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  const tb = gb * 1024;

  String scaled(double value, String unit) => value >= 100
      ? '${_count.format(value.round())} $unit'
      : '${value.toStringAsFixed(1)} $unit';

  if (bytes >= tb) return scaled(bytes / tb, 'TiB');
  if (bytes >= gb) return scaled(bytes / gb, 'GiB');
  if (bytes >= mb) return scaled(bytes / mb, 'MiB');
  return scaled(bytes / kb, 'KiB');
}

/// Between items in a line of facts, here and on the profile card. Wavehaus
/// draws its middle dot low and small, so it read as a full stop; its bullet
/// sits on the line's middle.
const permanenceSeparator = '  •  ';

/// A count and what it counts, with thousands separated: "1,776 files".
String permanenceCount(int n, String one) =>
    '${_count.format(n)} $one${n == 1 ? '' : 's'}';

void showPermanencePanel(BuildContext context, PermanenceSummary summary) {
  // Held from here because the profile card closes as it opens this, so
  // [context] is gone by the time Share is pressed: the share card is opened
  // from the navigator's own context, which outlives both.
  final navigator = Navigator.of(context);

  showArDriveDialog(
    context,
    content: _NoScrollbar(
      child: ArDriveStandardModalNew(
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
              navigator.pop();
              showPermanenceShare(navigator.context, summary);
            },
          ),
        ],
      ),
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
            permanenceCount(summary.fileCount, 'file'),
            permanenceCount(summary.driveCount, 'drive'),
            if (summary.firstYear != null) 'since ${summary.firstYear}',
          ].join(permanenceSeparator),
          style: typography.paragraphNormal(
            color: colors.textLow,
            fontWeight: ArFontWeight.book,
          ),
        ),
        if (summary.bytesByYear.isNotEmpty) ...[
          const SizedBox(height: 20),
          Semantics(
            // The chart is painted, so it says in words what it draws.
            label: 'Uploaded by year: ${[
              for (final year in summary.bytesByYear.entries)
                '${year.key}, ${_formatSize(year.value)}',
            ].join('; ')}',
            child: SizedBox(
              // Taller with each year past six, so every year keeps room for
              // its label.
              height: math.max(120, 20.0 * summary.bytesByYear.length),
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
          ),
        ],
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, box) {
          final spendTile = _SpendTile(
            spend: summary.spend,
            loadSpend: summary.loadSpend,
            cachedSpend: summary.cachedSpend,
            arSpend: summary.arSpend,
          );
          final costTile = _CostTile(cost: summary.costToday);

          // Side by side even on a phone, their notes wrapping by the word:
          // stacked, the panel no longer fit, and nothing said it scrolled.
          // Only a screen too narrow for that stacks them.
          if (box.maxWidth < 280) {
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
        const SizedBox(height: 12),
        _FinePrint(signInChain: summary.signInChain),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.note,
    this.extra,
    this.action,
    this.onAction,
  });

  final String label;
  final String value;
  final String note;

  /// A second figure under the note: AR paid directly, beside dollars.
  final String? extra;

  /// A link under the note, and what it does.
  final String? action;
  final VoidCallback? onAction;

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
          if (action != null) ...[
            const SizedBox(height: 6),
            ArDriveClickArea(
              child: GestureDetector(
                onTap: onAction,
                child: Semantics(
                  button: true,
                  child: Text(
                    action!,
                    style: typography.caption(
                      color: colors.textRed,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (extra != null) ...[
            const SizedBox(height: 6),
            Text(
              extra!,
              style: typography.caption(
                color: colors.textMid,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the network charges today: dollars, with the AR they come from
/// beside them - so it reads as the price of storage, not as ours.
class _CostTile extends StatelessWidget {
  const _CostTile({required this.cost});

  final Future<NetworkCost?>? cost;

  static const _label = 'COST TODAY';
  static const _note = 'Network price to store it';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NetworkCost?>(
      future: cost,
      builder: (context, snapshot) {
        if (cost != null && snapshot.connectionState != ConnectionState.done) {
          return const _Tile(label: _label, value: '...', note: _note);
        }

        final network = snapshot.data;

        if (network == null) {
          return const _Tile(
            label: _label,
            value: '-',
            note: "couldn't reach the network",
          );
        }

        final usd = network.usd;

        // Without a dollar rate, the AR price alone.
        if (usd == null) {
          return _Tile(
            label: _label,
            value: _formatAr(network.ar),
            note: _note,
          );
        }

        return _Tile(
          label: _label,
          value: formatUsd(usd),
          note: _note,
          extra: _formatAr(network.ar),
        );
      },
    );
  }
}

/// AR as the credits are shown: two places from one AR up, separated by
/// thousands ("343.40 AR"); below one, up to four, without trailing zeros
/// ("0.0373 AR", "0.5 AR").
String _formatAr(double ar) {
  if (ar > 0 && ar < 0.0001) {
    return '<0.0001 AR';
  }

  if (ar < 1) {
    final small = ar.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
    return '${small.endsWith('.') ? '${small}0' : small} AR';
  }

  return '${NumberFormat.decimalPatternDigits(decimalDigits: 2).format(ar)} AR';
}

/// When a reading was made: the time of day for today, the date for an
/// earlier day.
String _formatAsOf(DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final sameDay = local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;

  return sameDay
      ? DateFormat.jm().format(local)
      : DateFormat.MMMd().format(local);
}

/// Credits as a bare number, the unit said in the note beneath: two
/// places once there is a whole credit, four below that, separated by
/// thousands. A credit is a trillion winc, as an AR is a trillion winston.
String _formatCredits(BigInt winc) {
  final credits = winc / BigInt.from(10).pow(12);

  if (credits > 0 && credits < 0.0001) {
    return '<0.0001';
  }

  return NumberFormat.decimalPatternDigits(
    decimalDigits: credits >= 1 ? 2 : 4,
  ).format(credits);
}

/// What the wallet has spent, in what it spent it in: Turbo credits, and AR
/// paid directly. No dollars - nothing here is a price, so there is nothing
/// to set against what storage costs today.
class _SpendTile extends StatefulWidget {
  const _SpendTile({
    required this.spend,
    required this.loadSpend,
    required this.arSpend,
    this.cachedSpend,
  });

  final Future<SpendLookup>? spend;
  final Future<SpendLookup> Function()? loadSpend;
  final SpendEntry? cachedSpend;
  final Future<ArSpendTally>? arSpend;

  @override
  State<_SpendTile> createState() => _SpendTileState();
}

class _SpendTileState extends State<_SpendTile> {
  static const _label = 'SPENT';

  /// The credits being read: from the start, or once asked for.
  late Future<SpendLookup>? spend = widget.spend;

  Future<ArSpendTally>? get arSpend => widget.arSpend;

  @override
  void didUpdateWidget(covariant _SpendTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Another summary: whatever was read for the last one is not this one's.
    if (widget.spend != oldWidget.spend ||
        widget.loadSpend != oldWidget.loadSpend) {
      spend = widget.spend;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ArSpendTally>(
      future: arSpend,
      builder: (context, arSnapshot) {
        final arCounting = arSpend != null &&
            arSnapshot.connectionState != ConnectionState.done;
        final ar = arSnapshot.data;
        final paidAr = ar != null && ar.winston > BigInt.zero ? ar : null;

        String? arLine() {
          if (arCounting) {
            return 'counting AR paid directly...';
          }

          if (paidAr == null) {
            return null;
          }

          return '+ ${paidAr.complete ? '' : 'at least '}'
              '${_formatAr(paidAr.ar)} paid directly';
        }

        // AR on its own, when there are no credits to show beside it.
        _Tile arOnly({
          String when = '',
          String? action,
          VoidCallback? onAction,
        }) =>
            _Tile(
              label: _label,
              value: _formatAr(paidAr!.ar),
              note: (paidAr.complete
                      ? 'paid directly in AR'
                      : 'paid directly in AR, at least') +
                  when,
              action: action,
              onAction: onAction,
            );

        // What a reading of the credits shows. [asOf] is set for one that was
        // read earlier, and says when.
        Widget settled(
          SpendLookup? lookup, {
          DateTime? asOf,
          String? action,
          VoidCallback? onAction,
        }) {
          final credits = lookup?.creditsWinc;
          final when = asOf == null ? '' : ', as of ${_formatAsOf(asOf)}';

          if (lookup != null && lookup.tooMany) {
            return _Tile(
              label: _label,
              value: '-',
              note: 'more top-ups than we can count here$when',
              extra: arLine(),
              action: action,
              onAction: onAction,
            );
          }

          if (lookup == null || lookup.failed) {
            return paidAr != null
                ? arOnly(when: when, action: action, onAction: onAction)
                : _Tile(
                    label: _label,
                    value: '-',
                    note: "couldn't read your credits",
                    extra: arLine(),
                  );
          }

          if (credits == null || credits == BigInt.zero) {
            return paidAr != null
                ? arOnly(when: when, action: action, onAction: onAction)
                : _Tile(
                    label: _label,
                    value: '-',
                    note: (credits == null
                            ? 'no top-ups found'
                            : 'no credits used yet') +
                        when,
                    extra: arLine(),
                    action: action,
                    onAction: onAction,
                  );
          }

          return _Tile(
            label: _label,
            value: _formatCredits(credits),
            note: 'Turbo credits used$when',
            extra: arLine(),
            action: action,
            onAction: onAction,
          );
        }

        // Not read yet: this wallet signs to read them, and the reader has
        // not asked.
        final loadSpend = widget.loadSpend;
        final earlier = widget.cachedSpend;
        if (spend == null && loadSpend != null) {
          void ask() {
            final read = loadSpend();
            setState(() {
              spend = read;
            });
          }

          // Read before: show that, and leave the signing to the reader.
          if (earlier != null) {
            return settled(
              earlier.lookup,
              asOf: earlier.fetchedAt,
              action: 'Refresh credits used',
              onAction: ask,
            );
          }

          return _Tile(
            label: _label,
            value: paidAr == null ? '-' : _formatAr(paidAr.ar),
            note: paidAr == null
                ? 'your wallet signs to read your credits'
                : paidAr.complete
                    ? 'paid directly in AR'
                    : 'paid directly in AR, at least',
            action: 'Show credits used',
            onAction: ask,
            extra: paidAr == null ? arLine() : null,
          );
        }

        return FutureBuilder<SpendLookup>(
          future: spend,
          builder: (context, snapshot) {
            final reading = spend != null &&
                snapshot.connectionState != ConnectionState.done;

            if (reading && earlier != null) {
              return settled(earlier.lookup, asOf: earlier.fetchedAt);
            }

            if (reading) {
              return const _Tile(
                label: _label,
                value: '...',
                note: 'reading your credits',
              );
            }

            final lookup = snapshot.data;

            // A reading that failed leaves the earlier one standing.
            if (spend != null &&
                (lookup == null || lookup.failed) &&
                earlier != null) {
              return settled(earlier.lookup, asOf: earlier.fetchedAt);
            }

            return settled(spend == null ? null : lookup);
          },
        );
      },
    );
  }
}

/// How the panel's numbers are made, one tap away. Closed by default, so the
/// panel stays a summary; open, it says plainly what each figure is and is
/// not.
class _FinePrint extends StatefulWidget {
  const _FinePrint({this.signInChain});

  /// See [PermanenceSummary.signInChain].
  final String? signInChain;

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

    // Each point opens with the name of the figure it explains, as the
    // panel labels it.
    TextSpan lead(String figure) => TextSpan(
          text: figure,
          style: body.copyWith(
            color: colors.textHigh,
            fontWeight: ArFontWeight.semiBold.weight,
          ),
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
                      point(TextSpan(children: [
                        lead('Size'),
                        const TextSpan(
                          text: ' counts every version of every file in your '
                              'own drives synced on this device, once its '
                              'upload is confirmed. Data saved in more than '
                              'one place counts once. Hidden drives and '
                              "pinned files aren't included, so this can "
                              'differ from what your drives list adds up to.',
                        ),
                      ])),
                      point(TextSpan(children: [
                        lead('Spent'),
                        const TextSpan(
                          text: " is the Turbo credits you've used: "
                              'everything credited to this wallet, minus '
                              'your balance. It includes credits spent on '
                              'ArNS names and credits used by wallets you '
                              'shared them with. Under it is the AR this '
                              'wallet paid for direct uploads (network fees '
                              'and ArDrive tips), read from Arweave. Neither '
                              'is in dollars: credits and AR were bought at '
                              'different prices over time.',
                        ),
                        if (widget.signInChain != null)
                          TextSpan(
                            text: ' Credits shared from your '
                                "${widget.signInChain} wallet aren't counted.",
                          ),
                      ])),
                      point(TextSpan(children: [
                        lead('Cost today'),
                        const TextSpan(
                          text: " is the Arweave network's own price to "
                              'store this much data now, in AR, converted at '
                              "today's AR price. The network's price and "
                              "AR's dollar value both change. It isn't what "
                              "ArDrive or Turbo would charge, and it isn't a "
                              'bill or a quote.',
                        ),
                      ])),
                      point(TextSpan(
                        children: [
                          lead('Permanence'),
                          const TextSpan(
                            text: ' is provided by the Arweave network, not '
                                'by ArDrive. Arweave says its storage '
                                'endowment is designed to pay for storage for '
                                '200 years or more. See the ',
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

/// Hides the scrollbar of the modal's own scroll view, which draws it inside
/// the modal's padding, over the content. The panel still scrolls on a
/// screen too short for it - by touch, wheel or keyboard.
class _NoScrollbar extends StatelessWidget {
  const _NoScrollbar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: child,
      );
}

/// The text that goes with the share card. No dollar amounts: what someone
/// spent is theirs to tell. No promise of a duration, either.
String permanenceShareText(PermanenceSummary summary) => [
      '${_formatSize(summary.totalBytes)} of my files, stored permanently '
          'on Arweave.',
      if (summary.firstYear != null) 'Preserving since ${summary.firstYear}.',
      'ardrive.io',
    ].join(' ');

void showPermanenceShare(BuildContext context, PermanenceSummary summary) {
  showArDriveDialog(
    context,
    content: _NoScrollbar(child: _PermanenceShareDialog(summary: summary)),
  );
}

/// The share card with its text, to copy and to save. Both leave it open,
/// since a post usually wants the two, and each says when it is done.
class _PermanenceShareDialog extends StatefulWidget {
  const _PermanenceShareDialog({required this.summary});

  final PermanenceSummary summary;

  @override
  State<_PermanenceShareDialog> createState() => _PermanenceShareDialogState();
}

class _PermanenceShareDialogState extends State<_PermanenceShareDialog> {
  final _cardKey = GlobalKey();

  bool _copied = false;
  bool _saving = false;
  bool _saved = false;

  /// How long a button says it is done before it reads as itself again.
  static const _doneFor = Duration(seconds: 2);

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: permanenceShareText(widget.summary)),
    );

    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(_doneFor);
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _save() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

    if (boundary == null || _saving) {
      return;
    }

    setState(() => _saving = true);

    try {
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
    } catch (e) {
      logger.w('Could not save the permanence card: $e');
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;
    setState(() => _saved = true);
    await Future.delayed(_doneFor);
    if (mounted) setState(() => _saved = false);
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveStandardModalNew(
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
                key: _cardKey,
                child: PermanenceShareCard(summary: widget.summary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            permanenceShareText(widget.summary),
            style: typography.paragraphSmall(
              color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
              fontWeight: ArFontWeight.book,
            ),
          ),
        ],
      ),
      actions: [
        ModalAction(
          title: _copied ? 'Copied' : 'Copy text',
          customWidth: 120,
          action: _copy,
        ),
        ModalAction(
          title: _saving
              ? 'Saving...'
              : _saved
                  ? 'Saved'
                  : 'Download image',
          customWidth: 160,
          isEnable: !_saving,
          action: _save,
        ),
      ],
    );
  }
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
                  'stored permanently on Arweave',
                  style: typography.paragraphXLarge(
                    color: _text,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (summary.firstYear != null) 'Since ${summary.firstYear}',
                    permanenceCount(summary.fileCount, 'file'),
                  ].join(permanenceSeparator),
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
    final layers = bytesByYear.entries.toList();
    // No band thinner than a label, unless there are more years than fit:
    // then they share the height, rather than the oldest falling off the
    // top.
    final minBand = math.min(16.0, size.height / layers.length);
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
      //
      // On a log scale. Uploads vary by orders of magnitude - 30 MB one
      // year, 16 GB the next - and on a straight one a single big year left
      // every other year the same near-white.
      final logMin = math.log(math.max(minBytes, 1));
      final logRange = math.log(math.max(maxBytes, 1)) - logMin;
      final heat = logRange <= 0
          ? 1.0
          : (math.log(math.max(layers[i].value, 1)) - logMin) / logRange;
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

    TextPainter text(String value, TextStyle style) => TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: TextDirection.ltr,
        )..layout();

    final years = [
      for (final layer in layers)
        text('${layer.key}', labelStyle.copyWith(color: label)),
    ];
    final amounts = [
      for (final layer in layers)
        text(_formatSize(layer.value), mutedStyle.copyWith(color: muted)),
    ];
    final lineHeight = [...years, ...amounts]
        .fold<double>(0, (a, painter) => math.max(a, painter.height));

    // Each label beside the middle of its band, unless two thin years sit
    // together: then they are spread a line apart.
    final ys = spreadStrataLabels(
      [
        for (var i = 0; i < layers.length; i++)
          (tops[i] + (i == 0 ? size.height : tops[i - 1])) / 2,
      ],
      gap: lineHeight + 2,
      height: size.height,
    );

    for (var i = 0; i < layers.length; i++) {
      years[i].paint(
        canvas,
        Offset(bandWidth + 14, ys[i] - years[i].height / 2),
      );
      amounts[i].paint(
        canvas,
        Offset(bandWidth + 54, ys[i] - amounts[i].height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StrataPainter old) =>
      old.bytesByYear != bytesByYear ||
      old.brand != brand ||
      old.faint != faint;
}

/// Where each year's label goes: [mids] are the bands' middles, oldest
/// (lowest) first, and each label is moved as little as it takes to sit at
/// least [gap] from the next, inside [height].
@visibleForTesting
List<double> spreadStrataLabels(
  List<double> mids, {
  required double gap,
  required double height,
}) {
  final ys = List<double>.of(mids);

  // Up from the bottom: each one at least a gap above the one below it.
  for (var i = 0; i < ys.length; i++) {
    final ceiling = i == 0 ? height - gap / 2 : ys[i - 1] - gap;
    ys[i] = math.min(ys[i], ceiling);
  }

  // Down from the top: nothing pushed out of the top edge.
  for (var i = ys.length - 1; i >= 0; i--) {
    final floor = i == ys.length - 1 ? gap / 2 : ys[i + 1] + gap;
    ys[i] = math.max(ys[i], floor);
  }

  return ys;
}

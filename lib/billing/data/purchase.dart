import 'package:ardrive/turbo/utils/utils.dart';
import 'package:intl/intl.dart';

/// What a row of the purchase history is. The service's payload is an open
/// set: it also sends ArNS purchases, and may send kinds this build has never
/// heard of, which all land in [other].
enum PurchaseKind { card, crypto, other }

/// How many decimals a token's smallest unit has, and what to call it.
const _tokens = <String, ({int decimals, String label})>{
  'arweave': (decimals: 12, label: 'AR'),
  'ario': (decimals: 6, label: 'ARIO'),
  'base-ario': (decimals: 6, label: 'ARIO'),
  'ethereum': (decimals: 18, label: 'ETH'),
  'base-eth': (decimals: 18, label: 'ETH'),
  'solana': (decimals: 9, label: 'SOL'),
  'usdc': (decimals: 6, label: 'USDC'),
  'base-usdc': (decimals: 6, label: 'USDC'),
  'polygon-usdc': (decimals: 6, label: 'USDC'),
  'pol': (decimals: 18, label: 'POL'),
  'matic': (decimals: 18, label: 'POL'),
  'kyve': (decimals: 6, label: 'KYVE'),
};

/// One purchase from `GET /v1/account/payments`, read defensively: every
/// field may be missing, and amounts stay strings or [BigInt].
class Purchase {
  const Purchase({
    required this.kind,
    required this.rawType,
    required this.dateText,
    required this.date,
    required this.credits,
    required this.paymentAmount,
    required this.currency,
    required this.provider,
    required this.receiptId,
    required this.giftMessage,
    required this.tokenType,
    required this.tokenQuantity,
    required this.usdEquivalent,
    required this.transactionId,
    required this.detail,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final value = json[key];
      if (value == null) return null;
      final s = '$value';
      return s.isEmpty ? null : s;
    }

    final type = text('type');
    final kind = switch (type) {
      'fiat' => PurchaseKind.card,
      'crypto' => PurchaseKind.crypto,
      _ => PurchaseKind.other,
    };
    final dateText = text('date') ?? '';

    return Purchase(
      kind: kind,
      rawType: type,
      dateText: dateText,
      date: DateTime.tryParse(dateText),
      credits: BigInt.tryParse(text('wincCredited') ?? ''),
      paymentAmount: BigInt.tryParse(text('paymentAmount') ?? ''),
      currency: text('currencyType'),
      provider: text('paymentProvider'),
      receiptId: text('receiptId'),
      giftMessage: text('giftMessage'),
      tokenType: text('tokenType'),
      tokenQuantity: text('tokenQuantity'),
      usdEquivalent: double.tryParse(text('usdEquivalent') ?? ''),
      transactionId: text('transactionId'),
      detail: kind == PurchaseKind.other ? text('name') : null,
    );
  }

  final PurchaseKind kind;
  final String? rawType;
  final String dateText;
  final DateTime? date;

  /// Winston credits added; null when the row says none.
  final BigInt? credits;

  /// Card: the charge in the currency's minor unit.
  final BigInt? paymentAmount;
  final String? currency;
  final String? provider;
  final String? receiptId;
  final String? giftMessage;

  /// Crypto: the token and the amount in its smallest unit.
  final String? tokenType;
  final String? tokenQuantity;
  final double? usdEquivalent;
  final String? transactionId;

  /// For a kind this build doesn't know: a name to show, if the row has one.
  final String? detail;

  /// A grant has no charge: credits added for nothing.
  bool get isGrant =>
      kind == PurchaseKind.card &&
      (paymentAmount == null || paymentAmount! <= BigInt.zero);

  /// The transaction (crypto) or the receipt (card), whichever the row has.
  ({bool isTransaction, String value})? get reference {
    if (transactionId != null) {
      return (isTransaction: true, value: transactionId!);
    }
    if (receiptId != null) return (isTransaction: false, value: receiptId!);
    return null;
  }

  /// Where [transactionId] can be looked up, when the chain has an explorer.
  Uri? get explorerUri {
    final tx = transactionId;
    if (kind != PurchaseKind.crypto || tx == null) return null;
    final base = switch (tokenType) {
      'arweave' => 'https://viewblock.io/arweave/tx/',
      'ethereum' => 'https://etherscan.io/tx/',
      'base-eth' || 'base-usdc' || 'base-ario' => 'https://basescan.org/tx/',
      'solana' => 'https://solscan.io/tx/',
      _ => null,
    };
    return base == null ? null : Uri.parse('$base$tx');
  }

  /// "25.00 USD" style amount of a card row, in the currency's own symbol.
  String? get cardAmountText {
    if (kind != PurchaseKind.card || isGrant) return null;
    final minor = paymentAmount!;
    final code = (currency ?? 'usd').toUpperCase();
    final major = minor.toDouble() / 100;
    try {
      return NumberFormat.simpleCurrency(name: code).format(major);
    } catch (_) {
      return '${major.toStringAsFixed(2)} $code';
    }
  }

  /// "2.5 AR": the token amount in whole units, or only the token's name when
  /// the amount can't be read.
  String? get cryptoAmountText {
    if (kind != PurchaseKind.crypto) return null;
    final known = _tokens[tokenType];
    final label = known?.label ?? (tokenType ?? '').toUpperCase();
    final amount = _wholeUnits(tokenQuantity, known?.decimals, maxDecimals: 6);
    if (amount == null) return label.isEmpty ? null : label;
    return '$amount $label';
  }

  /// "~$18.00", or null when Turbo gave none (it sends 0 for tiny amounts).
  String? get usdText {
    final usd = usdEquivalent;
    if (kind != PurchaseKind.crypto || usd == null || usd <= 0) return null;
    if (usd < 0.005) return '<\$0.01';
    return '~\$${usd.toStringAsFixed(2)}';
  }

  String get dateLabel =>
      date == null ? dateText : DateFormat.yMMMd().format(date!.toLocal());

  String get creditsText => credits == null || credits! <= BigInt.zero
      ? ''
      : convertWinstonToCostString(credits!);
}

/// [quantity] (an integer in the token's smallest unit) as whole units, with
/// no more than [maxDecimals] places (all of them when null) and no trailing
/// zeros. Null when the amount or the token's decimals aren't known.
String? _wholeUnits(String? quantity, int? decimals, {int? maxDecimals}) {
  final value = BigInt.tryParse(quantity ?? '');
  if (value == null || decimals == null) return null;
  final text = value.abs().toString().padLeft(decimals + 1, '0');
  final whole = text.substring(0, text.length - decimals);
  var fraction = text.substring(text.length - decimals);
  if (maxDecimals != null && fraction.length > maxDecimals) {
    fraction = fraction.substring(0, maxDecimals);
  }
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  final sign = value < BigInt.zero ? '-' : '';
  return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
}

/// The Console's export: `Date, Method, Amount, USD Value, Credits,
/// Reference`, every cell quoted, rows joined by CRLF.
String purchasesCsv(List<Purchase> purchases) {
  String cell(String? value) => '"${(value ?? '').replaceAll('"', '""')}"';

  String credits(Purchase p) {
    final winc = p.credits;
    if (winc == null) return '';
    // Whole credits, exact: winston has 12 decimals.
    return _wholeUnits(winc.toString(), 12) ?? '';
  }

  final rows = <List<String?>>[
    ['Date', 'Method', 'Amount', 'USD Value', 'Credits', 'Reference'],
    for (final p in purchases)
      switch (p.kind) {
        PurchaseKind.crypto => [
            p.dateText,
            'Crypto',
            _csvCryptoAmount(p),
            p.usdEquivalent?.toStringAsFixed(2),
            credits(p),
            p.transactionId,
          ],
        PurchaseKind.card => [
            p.dateText,
            'Card',
            p.paymentAmount == null
                ? (p.currency ?? '').toUpperCase()
                : '${_wholeUnits(p.paymentAmount.toString(), 2)} '
                    '${(p.currency ?? 'usd').toUpperCase()}',
            (p.currency ?? 'usd').toLowerCase() == 'usd' &&
                    p.paymentAmount != null
                ? _wholeUnits(p.paymentAmount.toString(), 2)
                : '',
            credits(p),
            p.receiptId,
          ],
        PurchaseKind.other => [
            p.dateText,
            'Other',
            p.detail,
            '',
            credits(p),
            '',
          ],
      },
  ];

  return rows.map((r) => r.map(cell).join(',')).join('\r\n');
}

String _csvCryptoAmount(Purchase p) {
  final known = _tokens[p.tokenType];
  final label = known?.label ?? (p.tokenType ?? '').toUpperCase();
  final amount = _wholeUnits(p.tokenQuantity, known?.decimals);
  return amount == null ? label : '$amount $label';
}
